import CoreGraphics
import Foundation

public enum Handle: Sendable, Equatable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left   // rect-like shapes
    case start, end                                                              // line, arrow
}

public enum AnnotationHandles {
    /// Handles the shape offers, with their image-space positions. Rect-like: 8; line/arrow: start and end;
    /// freehand, text, step: none.
    public static func handles(for annotation: Annotation) -> [(handle: Handle, point: CGPoint)] {
        switch annotation.shape {
        case .arrow(let from, let to), .line(let from, let to):
            return [(.start, from), (.end, to)]
        case .rect(let rect), .ellipse(let rect), .blur(let rect, _), .highlight(let rect):
            return rectHandles(rect.standardized)
        case .freehand, .text, .step:
            return []
        }
    }

    private static func rectHandles(_ rect: CGRect) -> [(handle: Handle, point: CGPoint)] {
        [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY)),
        ]
    }

    /// The handle within `tolerance` (image pixels) of `point`, closest first.
    public static func handle(at point: CGPoint, in annotation: Annotation, tolerance: CGFloat) -> Handle? {
        var best: (handle: Handle, distance: CGFloat)?
        for (handle, p) in handles(for: annotation) {
            let distance = hypot(point.x - p.x, point.y - p.y)
            guard distance <= tolerance else { continue }
            if best == nil || distance < best!.distance {
                best = (handle, distance)
            }
        }
        return best?.handle
    }

    /// The annotation with `handle` dragged to `point`. Rect-like shapes keep the opposite edge fixed and are
    /// standardized (dragging past the opposite edge flips, never produces a negative size). Line/arrow move
    /// that endpoint.
    public static func resized(_ annotation: Annotation, handle: Handle, to point: CGPoint) -> Annotation {
        var copy = annotation
        switch annotation.shape {
        case .arrow(let from, let to):
            switch handle {
            case .start: copy.shape = .arrow(from: point, to: to)
            case .end: copy.shape = .arrow(from: from, to: point)
            default: break
            }
        case .line(let from, let to):
            switch handle {
            case .start: copy.shape = .line(from: point, to: to)
            case .end: copy.shape = .line(from: from, to: point)
            default: break
            }
        case .rect(let rect):
            copy.shape = .rect(resizedRect(rect, handle: handle, to: point))
        case .ellipse(let rect):
            copy.shape = .ellipse(resizedRect(rect, handle: handle, to: point))
        case .blur(let rect, let mode):
            copy.shape = .blur(resizedRect(rect, handle: handle, to: point), mode: mode)
        case .highlight(let rect):
            copy.shape = .highlight(resizedRect(rect, handle: handle, to: point))
        case .freehand, .text, .step:
            break
        }
        return copy
    }

    /// Moves the edge(s) `handle` names to `point`, keeps the opposite edge(s) fixed, then standardizes.
    private static func resizedRect(_ rect: CGRect, handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .topLeft:
            minX = point.x; minY = point.y
        case .top:
            minY = point.y
        case .topRight:
            maxX = point.x; minY = point.y
        case .right:
            maxX = point.x
        case .bottomRight:
            maxX = point.x; maxY = point.y
        case .bottom:
            maxY = point.y
        case .bottomLeft:
            minX = point.x; maxY = point.y
        case .left:
            minX = point.x
        case .start, .end:
            break
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    }
}
