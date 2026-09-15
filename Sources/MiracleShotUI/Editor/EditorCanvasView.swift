import AppKit
import MiracleShotCore

/// Flipped canvas that draws the rendered document, selection chrome, the in-progress shape and the crop
/// overlay, and forwards mouse and keyboard events to an `EditorSession`. Holds no logic of its own beyond
/// coordinate conversion and drawing; every decision comes from `EditorGeometry`/`EditorSession`.
@MainActor
final class EditorCanvasView: NSView {
    private static let padding: CGFloat = 24
    private static let handleSize: CGFloat = 8
    private static let dashPattern: [CGFloat] = [4, 3]

    var session: EditorSession
    /// Called after every handled event, so the toolbar can refresh undo/redo and tool state.
    var onChange: (() -> Void)?
    /// Called after every zoom change (including a refit on resize) with the percent label.
    var onZoomChange: ((String) -> Void)?

    private(set) var geometry: EditorGeometry
    private(set) var zoom: EditorZoom = .fit
    private var renderedImage: CGImage?
    private var renderedDocument: Document?
    private var textField: EditorTextField?
    private var clipViewObserver: NSObjectProtocol?

    init(session: EditorSession) {
        self.session = session
        self.geometry = EditorGeometry(scale: 1, origin: CGPoint(x: Self.padding, y: Self.padding), imageSize: session.document.sourceSize)
        super.init(frame: .zero)
        // Document view of an NSScrollView: sized by hand in `relayout()`, never by Auto Layout constraints.
        translatesAutoresizingMaskIntoConstraints = true
        rerender()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Whether the inline text editor is currently on screen.
    var isEditingText: Bool { textField != nil }

    /// The cached render (crop plus annotations, no background), for the toolbar's drag thumbnail.
    func currentRender() -> CGImage? { renderedImage }

    /// View points per image pixel that shows a Retina capture at its natural on-screen size.
    private var naturalScale: CGFloat { 1 / session.document.scaleFactor }

    // MARK: - Zoom and scrolling

    /// Becomes the document view of an `NSScrollView`'s clip view; watch its frame directly so a window
    /// resize (or any other clip view size change) relays out the canvas.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipViewObserver {
            NotificationCenter.default.removeObserver(clipViewObserver)
            self.clipViewObserver = nil
        }
        guard let clipView = superview as? NSClipView else { return }
        clipView.postsFrameChangedNotifications = true
        // View geometry notifications are posted on the main thread; handle them synchronously so the canvas
        // keeps up with a live window resize instead of trailing it by a run loop turn.
        clipViewObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: clipView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
        relayout()
    }

    /// Recomputes the frame and geometry for the current zoom against the clip view's current size, without
    /// moving the scroll offset. Called on clip view size changes and, with the anchor adjustment layered on
    /// top, from `setZoom`.
    func relayout() {
        guard let clipSize = enclosingScrollView?.contentView.bounds.size else { return }
        let scale = zoom.scale(imageSize: session.document.sourceSize, viewSize: clipSize, padding: Self.padding, natural: naturalScale)
        let scaledSize = CGSize(width: session.document.sourceSize.width * scale, height: session.document.sourceSize.height * scale)
        frame.size = CGSize(width: max(clipSize.width, scaledSize.width + 2 * Self.padding),
                            height: max(clipSize.height, scaledSize.height + 2 * Self.padding))
        geometry = EditorGeometry.layout(imageSize: session.document.sourceSize, scale: scale, viewSize: frame.size, padding: Self.padding)
        session.hitTolerance = geometry.imageLength(fromView: 6)
        session.handleTolerance = geometry.imageLength(fromView: 8)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onZoomChange?(EditorZoom.label(scale: geometry.scale, natural: naturalScale))
    }

    /// Sets `zoom` and keeps the image point under `anchor` (canvas coordinates) in the same place on screen:
    /// remembers that point, relays out, then scrolls so the point lands back under `anchor`.
    func setZoom(_ newZoom: EditorZoom, anchor: CGPoint) {
        // Same path as any other focus loss: commit whatever is being typed before the geometry moves under it.
        window?.makeFirstResponder(self)

        let imagePoint = geometry.imagePoint(fromView: anchor)
        zoom = newZoom
        relayout()

        guard let clipView = enclosingScrollView?.contentView else { return }
        let newAnchor = geometry.viewPoint(fromImage: imagePoint)
        var origin = clipView.bounds.origin
        origin.x += newAnchor.x - anchor.x
        origin.y += newAnchor.y - anchor.y
        clipView.scroll(to: clampedScrollOrigin(origin, clipView: clipView))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    /// Applies a keyboard zoom action, anchored at the center of the visible rect.
    func applyZoomAction(_ action: EditorShortcuts.ZoomAction) {
        let visible = enclosingScrollView?.documentVisibleRect ?? bounds
        let anchor = CGPoint(x: visible.midX, y: visible.midY)
        let newZoom: EditorZoom
        switch action {
        case .zoomIn: newZoom = zoom.zoomedIn(currentScale: geometry.scale, natural: naturalScale)
        case .zoomOut: newZoom = zoom.zoomedOut(currentScale: geometry.scale, natural: naturalScale)
        case .fit: newZoom = .fit
        case .actualSize: newZoom = .fixed(naturalScale)
        }
        setZoom(newZoom, anchor: anchor)
    }

    private func clampedScrollOrigin(_ origin: CGPoint, clipView: NSClipView) -> CGPoint {
        let maxX = max(0, frame.width - clipView.bounds.width)
        let maxY = max(0, frame.height - clipView.bounds.height)
        return CGPoint(x: min(max(origin.x, 0), maxX), y: min(max(origin.y, 0), maxY))
    }

    override func magnify(with event: NSEvent) {
        let anchor = convert(event.locationInWindow, from: nil)
        setZoom(EditorZoom.scaled(currentScale: geometry.scale, by: 1 + event.magnification, natural: naturalScale), anchor: anchor)
    }

    /// Cmd+wheel (or cmd+pinch-equivalent trackpad scroll) zooms, anchored at the cursor; plain wheel and
    /// trackpad scrolling fall through to `super` so the enclosing scroll view scrolls instead.
    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let factor = event.hasPreciseScrollingDeltas ? 1 + deltaY * 0.01 : 1 + deltaY * 0.1
        let anchor = convert(event.locationInWindow, from: nil)
        setZoom(EditorZoom.scaled(currentScale: geometry.scale, by: factor, natural: naturalScale), anchor: anchor)
    }

    // MARK: - Single entry point

    /// Handles `event`, applies the resulting effect, re-renders if the document changed, then repaints.
    func send(_ event: EditorEvent) {
        let effect = session.handle(event)
        if let effect { apply(effect) }
        if renderedDocument != session.document { rerender() }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onChange?()
    }

    private func apply(_ effect: EditorEffect) {
        switch effect {
        case .beginTextEditing(let id):
            beginTextEditing(id: id)
        case .endTextEditing:
            endTextEditing()
        }
    }

    private func rerender() {
        renderedImage = AnnotationRenderer.renderWithoutBackground(session.document)
        renderedDocument = session.document
    }

    // MARK: - Text editing

    private func beginTextEditing(id: UUID) {
        guard let annotation = session.document.annotation(id: id), case .text(let origin, let string) = annotation.shape else { return }
        let field = EditorTextField(text: string, fontSize: annotation.style.fontSize, scale: geometry.scale)
        field.onCommit = { [weak self] newValue in
            self?.send(.textCommitted(id: id, string: newValue))
        }
        field.onCancel = { [weak self] in
            self?.send(.textCancelled(id: id))
        }
        var frame = field.frame
        frame.origin = geometry.viewPoint(fromImage: origin)
        field.frame = frame
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    private func endTextEditing() {
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = imagePoint(for: event)
        if event.clickCount == 2, let text = textAnnotation(at: point) {
            send(.editText(id: text.id))
            return
        }
        send(.mouseDown(point, shift: event.modifierFlags.contains(.shift)))
    }

    override func mouseDragged(with event: NSEvent) {
        send(.mouseDragged(imagePoint(for: event)))
    }

    override func mouseUp(with event: NSEvent) {
        send(.mouseUp(imagePoint(for: event)))
    }

    private func imagePoint(for event: NSEvent) -> CGPoint {
        geometry.clamped(geometry.imagePoint(fromView: convert(event.locationInWindow, from: nil)))
    }

    /// The text annotation under `point`, if any, for double-click editing.
    private func textAnnotation(at point: CGPoint) -> Annotation? {
        guard let hit = AnnotationHitTest.hit(point, in: session.document.annotations, tolerance: session.hitTolerance, bounds: session.bounds) else {
            return nil
        }
        guard case .text = hit.shape else { return nil }
        return hit
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:   // Backspace, forward delete
            send(.deleteSelection)
        case 53:        // Escape
            send(.escape)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        let cursor: NSCursor
        if case .moving = session.transient {
            cursor = .openHand
        } else {
            cursor = session.tool == .select ? .arrow : .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        BrandPalette.ink.nsColor().setFill()
        bounds.fill()

        if session.tool == .crop {
            drawCropOverlay(ctx: ctx)
        } else {
            drawRenderedImage(ctx: ctx)
            drawInProgressShape(ctx: ctx)
            drawSelectionChrome()
        }
    }

    /// The cropped render at its place in the view; shown whenever the crop tool is not active.
    private func drawRenderedImage(ctx: CGContext) {
        guard let renderedImage else { return }
        let crop = session.document.effectiveCrop
        drawUpright(renderedImage, in: geometry.viewRect(fromImage: crop), ctx: ctx)
    }

    /// `CGContext.draw(_:in:)` ignores the view's flip, so in this y-down view a bitmap would land upside down;
    /// flip locally around the target rect.
    private func drawUpright(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.minY + rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    /// The shape being drawn right now (`session.transient == .drawing`). Every shape but blur draws for real,
    /// transformed into view space; blur only outlines its rect (a live per-frame Gaussian blur is too slow).
    private func drawInProgressShape(ctx: CGContext) {
        guard case .drawing(let annotation) = session.transient else { return }
        if case .blur(let rect, _) = annotation.shape {
            drawDashedOutline(rect.standardized)
            return
        }
        let crop = session.document.effectiveCrop
        ctx.saveGState()
        ctx.translateBy(x: geometry.origin.x, y: geometry.origin.y)
        ctx.scaleBy(x: geometry.scale, y: geometry.scale)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        AnnotationRenderer.draw(annotation, in: ctx, source: session.document.source, sourceOffset: crop.origin)
        ctx.restoreGState()
    }

    private func drawDashedOutline(_ imageRect: CGRect) {
        let path = NSBezierPath(rect: geometry.viewRect(fromImage: imageRect).insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.setLineDash(Self.dashPattern, count: Self.dashPattern.count, phase: 0)
        BrandPalette.lime.nsColor().setStroke()
        path.stroke()
    }

    /// Dashed bounds plus 8 pt handles around the selected annotation.
    private func drawSelectionChrome() {
        guard let selected = session.selected else { return }
        drawDashedOutline(AnnotationBounds.bounds(of: selected))
        for (_, point) in AnnotationHandles.handles(for: selected) {
            let center = geometry.viewPoint(fromImage: point)
            let handleRect = NSRect(x: center.x - Self.handleSize / 2, y: center.y - Self.handleSize / 2,
                                    width: Self.handleSize, height: Self.handleSize)
            BrandPalette.ink2.nsColor().setFill()
            NSBezierPath(rect: handleRect).fill()
            BrandPalette.lime.nsColor().setStroke()
            let handlePath = NSBezierPath(rect: handleRect.insetBy(dx: 0.5, dy: 0.5))
            handlePath.lineWidth = 1
            handlePath.stroke()
        }
    }

    /// The full source image dimmed, with the crop-in-progress rect undimmed, outlined, and labeled.
    private func drawCropOverlay(ctx: CGContext) {
        guard let cropRect = activeCropRect else { return }
        let source = session.document.source
        let viewFullRect = geometry.viewRect(fromImage: CGRect(origin: .zero, size: session.document.sourceSize))
        drawUpright(source, in: viewFullRect, ctx: ctx)

        BrandPalette.overlayDim.nsColor(alpha: BrandPalette.overlayDimAlpha).setFill()
        viewFullRect.fill()

        let viewCropRect = geometry.viewRect(fromImage: cropRect)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewCropRect).addClip()
        drawUpright(source, in: viewFullRect, ctx: ctx)
        NSGraphicsContext.restoreGraphicsState()

        BrandPalette.lime.nsColor().setStroke()
        let outline = NSBezierPath(rect: viewCropRect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1
        outline.stroke()

        drawCropSizeLabel(for: cropRect, near: viewCropRect)
    }

    /// The rect being cropped: the live drag rect while dragging, else the confirmed-but-pending crop.
    private var activeCropRect: CGRect? {
        if case .cropping(_, let rect) = session.transient { return rect }
        return session.pendingCrop
    }

    private func drawCropSizeLabel(for imageRect: CGRect, near viewRect: NSRect) {
        let text = "\(Int(imageRect.width)) × \(Int(imageRect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: BrandFont.mono(size: 11, weight: 500),
            .foregroundColor: BrandPalette.bone.nsColor(),
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        // Below the rect (greater y: this view is flipped), falling back inside it near the bottom edge
        // when there is no room below.
        var origin = NSPoint(x: viewRect.maxX - size.width - 12, y: viewRect.maxY + 12)
        if origin.y + size.height > bounds.maxY - 4 { origin.y = viewRect.maxY - size.height - 6 }
        origin.x = max(6, min(origin.x, bounds.maxX - size.width - 6))
        let box = NSRect(origin: origin, size: size).insetBy(dx: -6, dy: -3)
        BrandPalette.ink2.nsColor().setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }
}
