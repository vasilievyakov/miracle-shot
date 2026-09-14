import AppKit
import MiracleShotCore

@MainActor
public final class QuickPreviewPanel: PreviewPresenting {
    public enum Action: CaseIterable, Sendable {
        case edit, pin, ocr, ai, background, reveal

        var title: String {
            switch self {
            case .edit: return "Edit"
            case .pin: return "Pin"
            case .ocr: return "OCR"
            case .ai: return "AI"
            case .background: return "Background"
            case .reveal: return "Reveal"
            }
        }
    }

    public typealias Handler = @MainActor (Capture, URL?) -> Void

    /// Buttons are shown for exactly these actions, in `Action.allCases` order.
    public var handlers: [Action: Handler] = [:]
    public var timeout: TimeInterval = 6
    /// Presets offered by the Background button; the button is hidden when this is empty or no handler is set.
    public var backgroundPresets: [BackgroundPreset] = []
    /// Called with the previewed capture and the chosen preset. The panel dismisses itself first.
    public var onApplyBackground: (@MainActor (Capture, URL?, BackgroundPreset) -> Void)?

    private var panel: NSPanel?
    private var timing: PreviewTiming?
    private var timer: Timer?
    private var onDismiss: (@MainActor () -> Void)?
    private var current: (capture: Capture, fileURL: URL?)?

    public init() {}

    public func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void) {
        dismiss(animated: false)
        self.onDismiss = onDismiss
        current = (capture, fileURL)

        let buttons = Action.allCases.filter { isVisible($0, fileURL: fileURL) }.map { action -> BrandButton in
            let b = BrandButton(title: action.title, target: self, action: #selector(buttonPressed(_:)))
            b.tag = Action.allCases.firstIndex(of: action)!
            return b
        }
        let content = PreviewContentView(capture: capture, fileURL: fileURL, buttons: buttons)
        content.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        content.onPrimaryAction = { [weak self] in self?.run(self?.handlers[.edit] != nil ? .edit : .reveal) }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize

        let screen = NSScreen.underCursor ?? NSScreen.screens[0]
        let finalOrigin = NSPoint(x: screen.visibleFrame.maxX - size.width - 16, y: screen.visibleFrame.minY + 16)
        let panel = NSPanel(contentRect: NSRect(origin: NSPoint(x: finalOrigin.x, y: finalOrigin.y - 8), size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentView = content
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(finalOrigin)
        }
        self.panel = panel

        timing = PreviewTiming(duration: timeout, now: Self.now())
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    public func dismiss(animated: Bool) {
        timer?.invalidate()
        timer = nil
        timing = nil
        guard let panel else { return }
        self.panel = nil
        // Snapshot and clear now, not in the deferred completion: a `show` that arrives during the fade must not
        // have its own `onDismiss` fired or its `current` wiped by the previous preview's completion handler.
        let callback = onDismiss
        onDismiss = nil
        current = nil
        let finish: @MainActor () -> Void = {
            panel.orderOut(nil)
            callback?()
        }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: { Task { @MainActor in finish() } })
        } else {
            finish()
        }
    }

    // MARK: - Private

    private static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func tick() {
        guard timing != nil else { return }
        if timing!.tick(now: Self.now()) { dismiss(animated: true) }
    }

    private func hoverChanged(_ inside: Bool) {
        if inside { timing?.hoverBegan(now: Self.now()) } else { timing?.hoverEnded(now: Self.now()) }
    }

    private func isVisible(_ action: Action, fileURL: URL?) -> Bool {
        switch action {
        case .background: return onApplyBackground != nil && !backgroundPresets.isEmpty
        case .reveal: return handlers[.reveal] != nil && fileURL != nil   // nothing to reveal after a failed save
        default: return handlers[action] != nil
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        let action = Action.allCases[sender.tag]
        if action == .background { showBackgroundMenu(from: sender) } else { run(action) }
    }

    private func showBackgroundMenu(from button: NSView) {
        guard current != nil else { return }
        let menu = NSMenu()
        for (index, preset) in backgroundPresets.enumerated() {
            let item = NSMenuItem(title: preset.name, action: #selector(backgroundChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            // Rendered at 2x so the tile stays crisp on Retina menus.
            if let swatch = BackgroundRenderer.swatch(preset, size: 28) {
                item.image = NSImage(cgImage: swatch, size: NSSize(width: 14, height: 14))
            }
            menu.addItem(item)
        }
        // The menu runs its own event loop and the panel gets a mouseExited on the way in; hold the timer so the
        // preview cannot close underneath the open menu.
        timing?.hoverBegan(now: Self.now())
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        timing?.hoverEnded(now: Self.now())
    }

    @objc private func backgroundChosen(_ sender: NSMenuItem) {
        guard let current, let handler = onApplyBackground, backgroundPresets.indices.contains(sender.tag) else { return }
        let preset = backgroundPresets[sender.tag]
        let payload = current
        dismiss(animated: true)
        handler(payload.capture, payload.fileURL, preset)
    }

    private func run(_ action: Action) {
        guard let current, let handler = handlers[action] else { return }
        let payload = current
        dismiss(animated: true)
        handler(payload.capture, payload.fileURL)
    }
}
