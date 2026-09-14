import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// One CoreGraphics/CoreImage path for both the live canvas and export: crop -> annotations -> background.
/// Annotation coordinates are source pixels, origin top-left, y down; the context is flipped so vector drawing
/// maps directly, then unflipped again for image patches (blur/pixelate), which are plain pixel copies.
public enum AnnotationRenderer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Crop -> annotations -> background. `nil` only if a context cannot be made.
    public static func render(_ document: Document) -> CGImage? {
        guard let annotated = renderWithoutBackground(document) else { return nil }
        guard let background = document.background else { return annotated }
        return BackgroundRenderer.render(annotated, preset: background, scale: document.scaleFactor)
    }

    /// Crop and annotations without the background; the canvas shows this one.
    public static func renderWithoutBackground(_ document: Document) -> CGImage? {
        let crop = document.effectiveCrop
        let width = Int(crop.width)
        let height = Int(crop.height)
        guard width > 0, height > 0, let cropped = document.source.cropping(to: crop),
              let ctx = makeContext(width: width, height: height) else { return nil }

        // The crop draws unflipped, in the context's own device space.
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Flip for vector annotation coordinates (source pixels, origin top-left, y down), then shift so
        // full-image annotation coordinates land correctly inside the (possibly offset) crop.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -crop.minX, y: -crop.minY)
        for annotation in document.annotations {
            draw(annotation, in: ctx, source: document.source, sourceOffset: crop.origin)
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// Draws one annotation into `ctx` whose current transform maps image pixels (origin top-left, y down) to the
    /// target. Used by the canvas for the in-progress shape and by `render`. `source` is needed for blur patches
    /// (blur samples the original image, not just the visible crop). `sourceOffset` is the crop's origin in
    /// `source`, i.e. what to subtract from full-image annotation coordinates to land in `ctx`'s own pixel space.
    public static func draw(_ annotation: Annotation, in ctx: CGContext, source: CGImage, sourceOffset: CGPoint) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let style = annotation.style
        switch annotation.shape {
        case .arrow(let from, let to):
            drawArrow(from: from, to: to, style: style, ctx: ctx)
        case .line(let from, let to):
            drawLine(from: from, to: to, style: style, ctx: ctx)
        case .rect(let rect):
            drawRectOrEllipse(rect, style: style, ctx: ctx, ellipse: false)
        case .ellipse(let rect):
            drawRectOrEllipse(rect, style: style, ctx: ctx, ellipse: true)
        case .freehand(let points):
            drawFreehand(points, style: style, ctx: ctx)
        case .text(let origin, let string):
            drawText(origin: origin, string: string, style: style, ctx: ctx)
        case .step(let center, let number):
            drawStep(center: center, number: number, style: style, ctx: ctx)
        case .blur(let rect, let mode):
            drawBlur(rect: rect, mode: mode, source: source, sourceOffset: sourceOffset, ctx: ctx)
        case .highlight(let rect):
            drawHighlight(rect, style: style, ctx: ctx)
        }
    }

    // MARK: - Vector shapes

    private static func drawArrow(from: CGPoint, to: CGPoint, style: AnnotationStyle, ctx: CGContext) {
        guard from != to else { return }
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: style.lineWidth)
        let leftPoint = head.left
        let rightPoint = head.right
        let shaftEnd = head.shaftEnd

        ctx.setStrokeColor(style.strokeColor.cgColor())
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: from)
        ctx.addLine(to: shaftEnd)
        ctx.strokePath()

        ctx.setFillColor(style.strokeColor.cgColor())
        ctx.move(to: to)
        ctx.addLine(to: leftPoint)
        ctx.addLine(to: rightPoint)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawLine(from: CGPoint, to: CGPoint, style: AnnotationStyle, ctx: CGContext) {
        ctx.setStrokeColor(style.strokeColor.cgColor())
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }

    private static func drawRectOrEllipse(_ rect: CGRect, style: AnnotationStyle, ctx: CGContext, ellipse: Bool) {
        if let fillColor = style.fillColor {
            ctx.setFillColor(fillColor.cgColor())
            if ellipse { ctx.fillEllipse(in: rect) } else { ctx.fill(rect) }
        }
        // Inset by half the stroke width so the stroke stays inside the rect instead of straddling its edge.
        let strokeRect = rect.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2)
        ctx.setStrokeColor(style.strokeColor.cgColor())
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineJoin(.round)
        if ellipse { ctx.strokeEllipse(in: strokeRect) } else { ctx.stroke(strokeRect) }
    }

    private static func drawFreehand(_ points: [CGPoint], style: AnnotationStyle, ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.setStrokeColor(style.strokeColor.cgColor())
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: first)
        for point in points.dropFirst() { ctx.addLine(to: point) }
        ctx.strokePath()
    }

    private static func drawHighlight(_ rect: CGRect, style: AnnotationStyle, ctx: CGContext) {
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(style.strokeColor.cgColor(alpha: 0.35))
        ctx.fill(rect)
    }

    // MARK: - Text and step

    private static func drawText(origin: CGPoint, string: String, style: AnnotationStyle, ctx: CGContext) {
        guard !string.isEmpty else { return }
        guard let font = CoreTypeface.font(style.fontFamily, size: style.fontSize, weight: AnnotationTextWeight.forFamily(style.fontFamily)) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: style.strokeColor.cgColor(),
        ]
        let lines = string.components(separatedBy: "\n")
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let ctLines: [CTLine] = lines.map { line in
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
            var lineAscent: CGFloat = 0
            var lineDescent: CGFloat = 0
            var lineLeading: CGFloat = 0
            _ = CTLineGetTypographicBounds(ctLine, &lineAscent, &lineDescent, &lineLeading)
            ascent = max(ascent, lineAscent)
            descent = max(descent, lineDescent)
            leading = max(leading, lineLeading)
            return ctLine
        }
        let lineStep = ascent + descent + leading
        // Cancels the context's own y-flip so glyphs draw upright; `textPosition` still moves through the
        // (flipped) annotation coordinate space, so it steps down the page as `origin.y` would expect.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (index, line) in ctLines.enumerated() {
            ctx.textPosition = CGPoint(x: origin.x, y: origin.y + ascent + CGFloat(index) * lineStep)
            CTLineDraw(line, ctx)
        }
    }

    private static func drawStep(center: CGPoint, number: Int, style: AnnotationStyle, ctx: CGContext) {
        let radius = style.fontSize * 0.9
        let circleRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(style.strokeColor.cgColor())
        ctx.fillEllipse(in: circleRect)
        ctx.setStrokeColor(BrandPalette.ink.cgColor())
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: circleRect.insetBy(dx: 1, dy: 1))

        guard let font = CoreTypeface.font(.mono, size: style.fontSize, weight: 700) else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: BrandPalette.ink.cgColor(),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(number)", attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: center.x - width / 2, y: center.y + (ascent - descent) / 2)
        CTLineDraw(line, ctx)
    }

    // MARK: - Blur and pixelate

    private static func drawBlur(rect: CGRect, mode: BlurMode, source: CGImage, sourceOffset: CGPoint, ctx: CGContext) {
        let cropArea = CGRect(x: sourceOffset.x, y: sourceOffset.y, width: CGFloat(ctx.width), height: CGFloat(ctx.height))
        guard cropArea.intersects(rect) else { return }

        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        guard let clampFilter = CIFilter(name: "CIAffineClamp") else { return }
        clampFilter.setValue(CIImage(cgImage: source), forKey: kCIInputImageKey)
        clampFilter.setValue(NSAffineTransform(), forKey: kCIInputTransformKey)
        guard let clamped = clampFilter.outputImage else { return }

        let filtered: CIImage
        switch mode {
        case .gaussian:
            guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
            filter.setValue(clamped, forKey: kCIInputImageKey)
            filter.setValue(max(6, 0.012 * min(sourceWidth, sourceHeight)), forKey: kCIInputRadiusKey)
            guard let output = filter.outputImage else { return }
            filtered = output
        case .pixelate:
            guard let filter = CIFilter(name: "CIPixellate") else { return }
            filter.setValue(clamped, forKey: kCIInputImageKey)
            filter.setValue(max(8, 0.02 * min(sourceWidth, sourceHeight)), forKey: kCIInputScaleKey)
            // The rect's own origin, converted to CoreImage's y-up space, so blocks align with the rect.
            filter.setValue(CIVector(x: rect.origin.x, y: sourceHeight - rect.origin.y), forKey: kCIInputCenterKey)
            guard let output = filter.outputImage else { return }
            filtered = output
        }

        let ciRect = CGRect(x: rect.minX, y: sourceHeight - rect.maxY, width: rect.width, height: rect.height)
        let ciContext = CIContext(options: [.workingColorSpace: sRGB, .outputColorSpace: sRGB])
        guard let patch = ciContext.createCGImage(filtered, from: ciRect) else { return }

        // Image patches are plain pixel copies: undo the flip (reset to the context's own device space) before
        // drawing, rather than fight the flipped transform with a mirrored image.
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        let destRect = CGRect(x: rect.minX - sourceOffset.x, y: CGFloat(ctx.height) - (rect.maxY - sourceOffset.y),
                              width: rect.width, height: rect.height)
        ctx.clip(to: destRect)
        ctx.draw(patch, in: destRect)
        ctx.restoreGState()
    }

    // MARK: - Context

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
