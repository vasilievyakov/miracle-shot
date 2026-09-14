import CoreGraphics

/// Maps between the editor canvas view (points, origin top-left, y down, same convention as the
/// flipped NSView the canvas uses) and the source image (pixels, origin top-left, y down).
public struct EditorGeometry: Sendable, Equatable {
    /// View points per image pixel.
    public let scale: CGFloat
    /// Where the image's top-left lands in the view.
    public let origin: CGPoint
    public let imageSize: CGSize

    public init(scale: CGFloat, origin: CGPoint, imageSize: CGSize) {
        self.scale = scale
        self.origin = origin
        self.imageSize = imageSize
    }

    /// Fits `imageSize` (pixels) into `viewSize` minus `padding` on every side, never larger than `maxScale`
    /// (pass `1 / scaleFactor` so a Retina capture shows at its natural on-screen size), centered.
    /// Falls back to scale 1 and origin at padding when the image or the available space is empty.
    public static func fit(imageSize: CGSize, in viewSize: CGSize, padding: CGFloat, maxScale: CGFloat) -> EditorGeometry {
        let availableWidth = viewSize.width - 2 * padding
        let availableHeight = viewSize.height - 2 * padding
        guard imageSize.width > 0, imageSize.height > 0, availableWidth > 0, availableHeight > 0 else {
            return EditorGeometry(scale: 1, origin: CGPoint(x: padding, y: padding), imageSize: imageSize)
        }
        let scale = min(maxScale, availableWidth / imageSize.width, availableHeight / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (viewSize.width - scaledSize.width) / 2, y: (viewSize.height - scaledSize.height) / 2)
        return EditorGeometry(scale: scale, origin: origin, imageSize: imageSize)
    }

    public func imagePoint(fromView p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    public func viewPoint(fromImage p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * scale + origin.x, y: p.y * scale + origin.y)
    }

    public func imageRect(fromView r: CGRect) -> CGRect {
        CGRect(origin: imagePoint(fromView: r.origin), size: CGSize(width: r.width / scale, height: r.height / scale))
    }

    public func viewRect(fromImage r: CGRect) -> CGRect {
        CGRect(origin: viewPoint(fromImage: r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
    }

    /// `points` in the view converted to image pixels (tolerances, handle radii).
    public func imageLength(fromView points: CGFloat) -> CGFloat {
        points / scale
    }

    /// Clamps an image point into the image bounds.
    public func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), imageSize.width), y: min(max(p.y, 0), imageSize.height))
    }
}
