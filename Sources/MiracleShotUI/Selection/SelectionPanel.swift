import AppKit
import MiracleShotCore

@MainActor
final class SelectionPanel: NSPanel {
    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = SelectionView(screen: screen, mode: mode, controller: controller)
    }

    override var canBecomeKey: Bool { true }
}
