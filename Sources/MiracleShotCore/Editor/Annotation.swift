import CoreGraphics
import Foundation

/// A typeface family available to annotations. `CoreTypeface` resolves each case to a concrete font.
public enum FontFamily: String, Sendable, Equatable, CaseIterable {
    case text      // Onest
    case mono      // JetBrains Mono
    case display   // Geologica
}

/// Visual attributes shared by every annotation. Sizes are in source pixels.
public struct AnnotationStyle: Sendable, Equatable {
    public var strokeColor: BrandColor
    public var fillColor: BrandColor?
    public var lineWidth: CGFloat
    public var fontFamily: FontFamily
    public var fontSize: CGFloat

    public init(strokeColor: BrandColor = BrandPalette.lime, fillColor: BrandColor? = nil, lineWidth: CGFloat = 4,
                fontFamily: FontFamily = .text, fontSize: CGFloat = 28) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.fontFamily = fontFamily
        self.fontSize = fontSize
    }

    /// Defaults scaled for a capture at `scaleFactor` (a 2x screenshot gets 2x strokes).
    public static func `default`(scaleFactor: CGFloat) -> AnnotationStyle {
        AnnotationStyle(lineWidth: 4 * scaleFactor, fontSize: 28 * scaleFactor)
    }
}

public enum BlurMode: String, Sendable, Equatable { case gaussian, pixelate }

public enum AnnotationShape: Sendable, Equatable {
    case arrow(from: CGPoint, to: CGPoint)
    case line(from: CGPoint, to: CGPoint)
    case rect(CGRect)
    case ellipse(CGRect)
    case freehand([CGPoint])
    case text(origin: CGPoint, string: String)
    /// Numbered badge; `number` is kept in reading order by `Document.normalizeSteps()`.
    case step(center: CGPoint, number: Int)
    case blur(CGRect, mode: BlurMode)
    case highlight(CGRect)
}

public struct Annotation: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var shape: AnnotationShape
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), shape: AnnotationShape, style: AnnotationStyle) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    /// Axis-aligned bounds of the geometry alone (text and step bounds need metrics: see `AnnotationBounds` in Task 3).
    /// For `text` this returns a zero-size rect at the origin; for `step` a square of side `style.fontSize * 2` centered.
    public var geometryBounds: CGRect {
        switch shape {
        case .arrow(let from, let to), .line(let from, let to):
            return CGRect(x: from.x, y: from.y, width: to.x - from.x, height: to.y - from.y).standardized
        case .rect(let rect), .ellipse(let rect), .blur(let rect, _), .highlight(let rect):
            return rect.standardized
        case .freehand(let points):
            guard let first = points.first else { return .zero }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for point in points.dropFirst() {
                minX = min(minX, point.x)
                minY = min(minY, point.y)
                maxX = max(maxX, point.x)
                maxY = max(maxY, point.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text(let origin, _):
            return CGRect(origin: origin, size: .zero)
        case .step(let center, _):
            let side = style.fontSize * 2
            return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }
    }

    /// Same shape shifted by `delta`.
    public func moved(by delta: CGPoint) -> Annotation {
        var copy = self
        func shift(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.x, y: point.y + delta.y) }
        func shift(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: delta.x, dy: delta.y) }
        switch shape {
        case .arrow(let from, let to):
            copy.shape = .arrow(from: shift(from), to: shift(to))
        case .line(let from, let to):
            copy.shape = .line(from: shift(from), to: shift(to))
        case .rect(let rect):
            copy.shape = .rect(shift(rect))
        case .ellipse(let rect):
            copy.shape = .ellipse(shift(rect))
        case .freehand(let points):
            copy.shape = .freehand(points.map(shift))
        case .text(let origin, let string):
            copy.shape = .text(origin: shift(origin), string: string)
        case .step(let center, let number):
            copy.shape = .step(center: shift(center), number: number)
        case .blur(let rect, let mode):
            copy.shape = .blur(shift(rect), mode: mode)
        case .highlight(let rect):
            copy.shape = .highlight(shift(rect))
        }
        return copy
    }
}
