import AppKit
import MiracleShotCore

/// Small floating status panel shown while a scrolling capture is in progress: reports progress and reads Return
/// and Escape without ever taking focus away from the window being scrolled.
@MainActor
final class ScrollHUDPanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    var text: String = "" {
        didSet { relayout() }
    }

    private let label = NSTextField(labelWithString: "")
    /// Resolved once at construction so every later resize keeps the same horizontal center and top offset.
    private let targetScreen: NSScreen?

    private static let horizontalPadding: CGFloat = 16
    private static let verticalPadding: CGFloat = 10
    private static let topOffset: CGFloat = 12

    init(anchorWindow: WindowInfo) {
        targetScreen = Self.screen(containing: anchorWindow)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        label.font = BrandFont.mono(size: 12, weight: 500)
        label.textColor = BrandPalette.bone.nsColor()

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = BrandPalette.ink2.cgColor()
        container.layer?.cornerRadius = 8
        container.addSubview(label)
        contentView = container

        relayout()
    }

    override var canBecomeKey: Bool { true }

    func show() {
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()   // Return, keypad Enter
        case 53: onEscape?()       // Escape
        default: super.keyDown(with: event)
        }
    }

    private func relayout() {
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + Self.horizontalPadding * 2,
                          height: label.frame.height + Self.verticalPadding * 2)
        let visible = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - Self.topOffset)
        setFrame(NSRect(origin: origin, size: size), display: true)
        label.setFrameOrigin(NSPoint(x: Self.horizontalPadding, y: Self.verticalPadding))
        contentView?.frame = NSRect(origin: .zero, size: size)
    }

    /// The screen whose frame contains the window's center, flipped from CG's top-left origin to AppKit's
    /// bottom-left origin; falls back to the main screen when no screen matches (or none exists).
    private static func screen(containing window: WindowInfo) -> NSScreen? {
        let flippedCenter = NSPoint(x: window.frame.midX, y: NSScreen.primaryHeight - window.frame.midY)
        return NSScreen.screens.first { $0.frame.contains(flippedCenter) } ?? NSScreen.main
    }
}
