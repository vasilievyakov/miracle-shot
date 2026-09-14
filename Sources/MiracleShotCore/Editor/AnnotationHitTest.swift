import CoreGraphics
import Foundation

public enum AnnotationHitTest {
    /// Topmost annotation under `point` (last in `annotations` is topmost). `tolerance` in image pixels is
    /// added to half the stroke width. rect/ellipse/blur/highlight: inside the rect (ellipse: inside the
    /// ellipse) or within tolerance of the border; line/arrow/freehand: distance to any segment <= tolerance +
    /// lineWidth / 2; text: inside `textBounds` (provided by the caller through `bounds(for:)`); step: within
    /// radius `fontSize` of the center.
    public static func hit(_ point: CGPoint, in annotations: [Annotation], tolerance: CGFloat,
                           bounds: (Annotation) -> CGRect) -> Annotation? {
        for annotation in annotations.reversed() where isHit(point, annotation, tolerance: tolerance, bounds: bounds) {
            return annotation
        }
        return nil
    }

    private static func isHit(_ point: CGPoint, _ annotation: Annotation, tolerance: CGFloat,
                              bounds: (Annotation) -> CGRect) -> Bool {
        let halfStroke = annotation.style.lineWidth / 2
        switch annotation.shape {
        case .rect(let rect), .blur(let rect, _), .highlight(let rect):
            return distance(from: point, toRect: rect.standardized) <= tolerance
        case .ellipse(let rect):
            let grown = rect.standardized.insetBy(dx: -tolerance, dy: -tolerance)
            guard grown.width > 0, grown.height > 0 else { return false }
            let rx = grown.width / 2, ry = grown.height / 2
            let dx = (point.x - grown.midX) / rx
            let dy = (point.y - grown.midY) / ry
            return dx * dx + dy * dy <= 1
        case .line(let from, let to), .arrow(let from, let to):
            return distance(from: point, toSegment: from, to) <= tolerance + halfStroke
        case .freehand(let points):
            guard let first = points.first else { return false }
            guard points.count > 1 else {
                return distance(from: point, toSegment: first, first) <= tolerance + halfStroke
            }
            for i in 0..<(points.count - 1) where distance(from: point, toSegment: points[i], points[i + 1]) <= tolerance + halfStroke {
                return true
            }
            return false
        case .text:
            return bounds(annotation).contains(point)
        case .step(let center, _):
            return hypot(point.x - center.x, point.y - center.y) <= annotation.style.fontSize
        }
    }

    /// Distance from `p` to the (filled) axis-aligned rect: zero when `p` is inside, else the distance to the
    /// nearest border point.
    private static func distance(from p: CGPoint, toRect rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
        let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
        return hypot(dx, dy)
    }

    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        let projected = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - projected.x, p.y - projected.y)
    }
}
