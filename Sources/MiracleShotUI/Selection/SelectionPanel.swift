import AppKit
import MiracleShotCore

@MainActor
final class SelectionPanel: NSPanel {
    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController, windows: [WindowInfo], frozen: CGImage?) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = SelectionView(screen: screen, mode: mode, controller: controller, windows: windows, frozen: frozen)
    }

    override var canBecomeKey: Bool { true }

    /// Key status alone does not route key events to the content view; the first responder must be set explicitly,
    /// otherwise Escape does nothing until the first click.
    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(contentView)
    }

    /// Another of our panels may be taking key status (multi-display drag), so the controller checks asynchronously
    /// whether any overlay panel is still key and cancels only when focus really left the overlay.
    override func resignKey() {
        super.resignKey()
        (contentView as? SelectionView)?.controller.keyStatusChanged()
    }
}
