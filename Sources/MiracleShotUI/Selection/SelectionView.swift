import AppKit
import MiracleShotCore

/// Draws the frozen background, the dimming, the magnifier, the rubber-band rectangle, the size label and the
/// window highlight, and converts events into CG global coordinates.
@MainActor
final class SelectionView: NSView {
    private static let snapThreshold: CGFloat = 8
    private static let magnifierSize: CGFloat = 120
    private static let magnifierOffset: CGFloat = 20
    private static let magnifierPixels = 15   // source points shown in the magnifier

    private let screen: NSScreen
    private let mode: CaptureMode
    unowned let controller: SelectionOverlayController
    private let windows: [WindowInfo]
    private var frozen: CGImage?
    /// View-space region drawn dynamically last frame (magnifier, highlight, label); only it and the new one repaint.
    private var lastDynamicRegion: NSRect = .zero
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var cursor: CGPoint?
    private var hoveredWindow: WindowInfo?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, mode: CaptureMode, controller: SelectionOverlayController, windows: [WindowInfo], frozen: CGImage?) {
        self.screen = screen
        self.mode = mode
        self.controller = controller
        self.windows = windows
        self.frozen = frozen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Events

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller.finish(with: nil) }   // Escape
    }

    func setFrozen(_ image: CGImage) {
        frozen = image
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        cursor = cgPoint(from: event)
        hoveredWindow = cursor.flatMap { SelectionGeometry.window(at: $0, in: windows) }
        invalidateDynamicRegion()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = cgPoint(from: event)
        selection = nil
        invalidateDynamicRegion()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = cgPoint(from: event)
        cursor = point
        var rect = SelectionGeometry.rect(from: start, to: point)
        if !event.modifierFlags.contains(.option) {
            rect = SelectionGeometry.snapped(rect, to: windows, threshold: Self.snapThreshold)
        }
        selection = rect
        invalidateDynamicRegion()
    }

    /// Repaints only the union of the previous and the current dynamic region instead of the whole 5K frame.
    private func invalidateDynamicRegion() {
        let region = currentDynamicRegion()
        setNeedsDisplay(lastDynamicRegion.union(region))
        lastDynamicRegion = region
    }

    private func currentDynamicRegion() -> NSRect {
        var region = NSRect.zero
        if let highlight = currentHighlight, let viewRect = viewRect(fromCG: highlight) {
            // The size label sits within 40 pt below or inside the rect.
            region = region.union(viewRect.insetBy(dx: -40, dy: -40))
        }
        if let cursor, let frame = magnifierViewFrame(forCG: cursor) {
            region = region.union(frame.insetBy(dx: -2, dy: -2))
        }
        return region
    }

    private var currentHighlight: CGRect? {
        selection ?? (dragStart == nil && mode == .window ? hoveredWindow?.frame : nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let end = cgPoint(from: event)
        dragStart = nil
        if SelectionGeometry.isClick(from: start, to: end) {
            if let hovered = SelectionGeometry.window(at: end, in: windows) {
                controller.finish(with: .window(hovered))
            } else {
                controller.finish(with: nil)
            }
            return
        }
        guard let selection, selection.width >= 1, selection.height >= 1 else { controller.finish(with: nil); return }
        let rect = SelectionGeometry.pixelAligned(selection, scale: screen.backingScaleFactor)
        controller.finish(with: .area(rect: rect, displayID: screen.displayID))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if let frozen {
            NSGraphicsContext.current?.cgContext.draw(frozen, in: bounds)
        }
        BrandPalette.overlayDim.nsColor(alpha: BrandPalette.overlayDimAlpha).setFill()
        bounds.fill()

        if let highlight = currentHighlight, let viewRect = viewRect(fromCG: highlight) {
            if let frozen {
                NSGraphicsContext.saveGraphicsState()
                viewRect.clip()
                NSGraphicsContext.current?.cgContext.draw(frozen, in: bounds)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                NSColor.clear.setFill()
                viewRect.fill(using: .copy)
            }
            BrandPalette.lime.nsColor().setStroke()
            let path = NSBezierPath(rect: viewRect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
            drawSizeLabel(for: highlight, near: viewRect)
        }

        if let cursor, let viewCursor = viewPoint(fromCG: cursor), screenContains(cursor) {
            drawMagnifier(at: viewCursor, cgCursor: cursor)
        }
    }

    private func drawSizeLabel(for cgRect: CGRect, near viewRect: NSRect) {
        let text = "\(Int(cgRect.width)) × \(Int(cgRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: BrandPalette.bone.nsColor(),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var origin = NSPoint(x: viewRect.maxX - size.width - 12, y: viewRect.minY - size.height - 12)
        if origin.y < 4 { origin.y = viewRect.minY + 6 }
        origin.x = max(6, min(origin.x, bounds.maxX - size.width - 6))
        let box = NSRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        BrandPalette.ink2.nsColor().setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }

    /// Magnifier frame in view coordinates for a cursor in CG global coordinates; nil when off this screen.
    private func magnifierViewFrame(forCG cgCursor: CGPoint) -> NSRect? {
        guard screenContains(cgCursor) else { return nil }
        let screenBounds = CGRect(origin: .zero, size: bounds.size)
        let cgFrame = SelectionGeometry.magnifierFrame(
            cursor: CGPoint(x: cgCursor.x - screenFrameCG.minX, y: cgCursor.y - screenFrameCG.minY),
            size: Self.magnifierSize, offset: Self.magnifierOffset, in: screenBounds)
        // Local CG (top-left) -> view (bottom-left).
        return NSRect(x: cgFrame.minX, y: bounds.height - cgFrame.maxY, width: cgFrame.width, height: cgFrame.height)
    }

    private func drawMagnifier(at viewCursor: NSPoint, cgCursor: CGPoint) {
        guard let frozen, let frame = magnifierViewFrame(forCG: cgCursor) else { return }
        let scale = screen.backingScaleFactor

        let half = CGFloat(Self.magnifierPixels) / 2
        let localX = cgCursor.x - screenFrameCG.minX
        let localY = cgCursor.y - screenFrameCG.minY
        let sourceRect = CGRect(x: (localX - half) * scale, y: (localY - half) * scale,
                                width: CGFloat(Self.magnifierPixels) * scale, height: CGFloat(Self.magnifierPixels) * scale)
        guard let crop = frozen.cropping(to: sourceRect) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).addClip()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSGraphicsContext.current?.cgContext.draw(crop, in: frame)
        // Pixel grid and center crosshair.
        BrandPalette.line.nsColor(alpha: 0.6).setStroke()
        let cell = frame.width / CGFloat(Self.magnifierPixels)
        for i in 1..<Self.magnifierPixels {
            let x = frame.minX + CGFloat(i) * cell
            let y = frame.minY + CGFloat(i) * cell
            NSBezierPath.strokeLine(from: NSPoint(x: x, y: frame.minY), to: NSPoint(x: x, y: frame.maxY))
            NSBezierPath.strokeLine(from: NSPoint(x: frame.minX, y: y), to: NSPoint(x: frame.maxX, y: y))
        }
        BrandPalette.lime.nsColor().setStroke()
        let center = NSRect(x: frame.midX - cell / 2, y: frame.midY - cell / 2, width: cell, height: cell)
        NSBezierPath(rect: center).stroke()
        NSGraphicsContext.restoreGraphicsState()
        BrandPalette.lime.nsColor().setStroke()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    // MARK: Coordinates

    private var screenFrameCG: CGRect {
        SelectionGeometry.flipped(screen.frame, primaryScreenHeight: NSScreen.primaryHeight)
    }

    private func screenContains(_ cgPoint: CGPoint) -> Bool { screenFrameCG.contains(cgPoint) }

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

    private func viewPoint(fromCG point: CGPoint) -> NSPoint? {
        guard let window else { return nil }
        let appKit = SelectionGeometry.flipped(point, primaryScreenHeight: NSScreen.primaryHeight)
        return convert(window.convertPoint(fromScreen: appKit), from: nil)
    }
}
