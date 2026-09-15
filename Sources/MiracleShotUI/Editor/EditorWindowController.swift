import AppKit
import MiracleShotCore

/// Owns the editor window: builds the toolbar and canvas for a capture, wires shortcuts, and exports through
/// Copy (pasteboard) and Done (`onDone`, then close without asking). Only one editor window is open at a time;
/// opening a new capture while one is open with changes asks to discard it first.
@MainActor
public final class EditorWindowController: NSObject, NSWindowDelegate {
    private static let minSize = NSSize(width: 720, height: 520)
    private static let windowPadding: CGFloat = 48
    private static let maxScreenFraction: CGFloat = 0.85

    private var window: EditorWindow?
    private var toolbar: EditorToolbar?
    private var canvas: EditorCanvasView?
    private var onDone: ((CGImage) -> Void)?

    override public init() { super.init() }

    /// Opens `capture` for editing. If a window is already open with unsaved changes, asks to discard it first;
    /// otherwise (or once confirmed) the window is rebuilt for the new capture. `window.close()` (unlike
    /// `performClose`) never consults `windowShouldClose`, so this replacement never asks a second time.
    public func open(capture: Capture, presets: [BackgroundPreset], onDone: @escaping (CGImage) -> Void) {
        if window != nil {
            if hasUnsavedChanges {
                let alert = NSAlert()
                alert.messageText = "Discard the current edit?"
                alert.addButton(withTitle: "Discard")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            window?.close()
        }
        self.onDone = onDone
        buildWindow(capture: capture, presets: presets)
    }

    // MARK: - Building

    private func buildWindow(capture: Capture, presets: [BackgroundPreset]) {
        let document = Document(source: capture.image, scaleFactor: capture.scaleFactor)
        let session = EditorSession(document: document, style: .default(scaleFactor: capture.scaleFactor))
        let canvas = EditorCanvasView(session: session)
        let toolbar = EditorToolbar(presets: presets)

        let window = EditorWindow(canvas: canvas, contentRect: Self.windowRect(for: capture),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable])
        window.title = "Miracle Shot Editor"
        window.contentMinSize = Self.minSize
        window.isReleasedWhenClosed = false
        window.backgroundColor = BrandPalette.ink.nsColor()
        window.delegate = self

        let stack = NSStackView(views: [toolbar, canvas])
        stack.orientation = .vertical
        stack.spacing = 0
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            canvas.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
        window.contentView = stack

        canvas.onChange = { [weak toolbar, weak canvas] in
            guard let toolbar, let canvas else { return }
            toolbar.refresh(from: canvas.session)
        }
        toolbar.onEvent = { [weak canvas] event in canvas?.send(event) }
        toolbar.onCopy = { [weak self] in self?.copy() }
        toolbar.onDone = { [weak self] in self?.done() }
        toolbar.onCropApply = { [weak canvas] in canvas?.send(.cropConfirm) }
        toolbar.onCropCancel = { [weak canvas] in canvas?.send(.cropCancel) }
        window.onCopy = { [weak self] in self?.copy() }

        toolbar.refresh(from: session)

        self.window = window
        self.toolbar = toolbar
        self.canvas = canvas

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    // MARK: - Export

    private func copy() {
        guard let document = canvas?.session.document, let rendered = AnnotationRenderer.render(document) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        if let png = ImageCodec.pngData(from: rendered) {
            pasteboard.setData(png, forType: .png)
        }
        let image = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        if let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// `window.close()`, not `performClose`: Done skips the confirmation on purpose and must not ask again.
    private func done() {
        guard let document = canvas?.session.document, let rendered = AnnotationRenderer.render(document) else { return }
        onDone?(rendered)
        window?.close()
    }

    // MARK: - Discard confirmation

    private var hasUnsavedChanges: Bool {
        guard let document = canvas?.session.document else { return false }
        return !document.annotations.isEmpty || document.cropRect != nil || document.background != nil
    }

    /// Only reached through `performClose` (Cmd+W, or the red close-button widget); `window.close()` never
    /// consults the delegate, so Done and the reopen-replace path in `open()` never trigger this.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard changes?"
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        toolbar = nil
        canvas = nil
        onDone = nil
    }

    // MARK: - Sizing

    /// Natural image size plus the toolbar and padding, capped at 85 percent of the screen's visible frame,
    /// centered on the screen under the cursor.
    private static func windowRect(for capture: Capture) -> NSRect {
        let naturalSize = NSSize(width: CGFloat(capture.pixelWidth) / capture.scaleFactor,
                                 height: CGFloat(capture.pixelHeight) / capture.scaleFactor)
        let screen = NSScreen.underCursor ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Cap to the screen first, then apply the floor, so the window never opens below its own minimum.
        var size = NSSize(width: naturalSize.width + windowPadding,
                          height: naturalSize.height + EditorToolbar.height + windowPadding)
        size.width = max(minSize.width, min(size.width, visible.width * maxScreenFraction))
        size.height = max(minSize.height, min(size.height, visible.height * maxScreenFraction))

        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        return NSRect(origin: origin, size: size)
    }
}

/// Routes Cmd shortcuts (Copy, Close, undo/redo) through `performKeyEquivalent`, and every other editor
/// shortcut through `EditorShortcuts` in `keyDown`, unless the inline text editor is on screen.
@MainActor
private final class EditorWindow: NSWindow {
    private let canvas: EditorCanvasView
    var onCopy: (() -> Void)?

    init(canvas: EditorCanvasView, contentRect: NSRect, styleMask: NSWindow.StyleMask) {
        self.canvas = canvas
        super.init(contentRect: contentRect, styleMask: styleMask, backing: .buffered, defer: false)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        // With no main menu (LSUIElement) nothing forwards the standard edit commands to the inline text field,
        // so while an annotation is being typed they are sent to the responder chain by hand.
        if canvas.isEditingText {
            let editing: [String: Selector] = [
                "c": #selector(NSText.copy(_:)), "x": #selector(NSText.cut(_:)), "v": #selector(NSText.paste(_:)),
                "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:")),
            ]
            if let selector = editing[key] {
                return NSApp.sendAction(selector, to: nil, from: nil)
            }
        }
        switch key {
        case "c":
            onCopy?()
            return true
        case "z":
            canvas.send(event.modifierFlags.contains(.shift) ? .redo : .undo)
            return true
        case "w":
            performClose(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !canvas.isEditingText, let key = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }
        let cropActive = canvas.session.tool == .crop
        guard let mapped = EditorShortcuts.event(forKey: key, modifiers: event.modifierFlags, cropActive: cropActive) else {
            super.keyDown(with: event)
            return
        }
        canvas.send(mapped)
    }
}
