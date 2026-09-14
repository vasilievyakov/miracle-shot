import AppKit
import MiracleShotCore

/// Draws the dimming, the rubber-band rectangle and converts events into CG global coordinates.
@MainActor
final class SelectionView: NSView {
    private let screen: NSScreen
    private let mode: CaptureMode
    private unowned let controller: SelectionOverlayController
    private var dragStart: CGPoint?
    private var selection: CGRect?

    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController) {
        self.screen = screen
        self.mode = mode
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller.finish(with: nil) }   // Escape
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = cgPoint(from: event)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        selection = SelectionGeometry.rect(from: start, to: cgPoint(from: event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = cgPoint(from: event)
        dragStart = nil
        if SelectionGeometry.isClick(from: start, to: end) {
            controller.finish(with: nil)
            return
        }
        let rect = SelectionGeometry.pixelAligned(SelectionGeometry.rect(from: start, to: end), scale: screen.backingScaleFactor)
        controller.finish(with: .area(rect: rect, displayID: screen.displayID))
    }

    override func draw(_ dirtyRect: NSRect) {
        BrandPalette.overlayDim.nsColor(alpha: BrandPalette.overlayDimAlpha).setFill()
        bounds.fill()
        guard let selection, let viewRect = viewRect(fromCG: selection) else { return }
        NSColor.clear.setFill()
        viewRect.fill(using: .copy)
        BrandPalette.lime.nsColor().setStroke()
        let path = NSBezierPath(rect: viewRect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: Coordinates

    private func cgPoint(from event: NSEvent) -> CGPoint {
        guard let window else { return .zero }
        let global = window.convertPoint(toScreen: event.locationInWindow)
        return SelectionGeometry.flipped(global, primaryScreenHeight: NSScreen.primaryHeight)
    }

    private func viewRect(fromCG rect: CGRect) -> NSRect? {
        guard let window else { return nil }
        let appKit = SelectionGeometry.flipped(rect, primaryScreenHeight: NSScreen.primaryHeight)
        return convert(window.convertFromScreen(appKit), from: nil)
    }
}
