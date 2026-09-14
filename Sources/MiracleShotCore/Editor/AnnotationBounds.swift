import CoreGraphics
import CoreText
import Foundation

/// Bounds that account for text and step metrics. `Annotation.geometryBounds` alone is only a rough placeholder
/// for those two shapes (a zero-size rect for text, a fixed square for step); every other shape's bounds equal
/// `geometryBounds` exactly, so this simply forwards to it.
public enum AnnotationBounds {
    public static func bounds(of annotation: Annotation) -> CGRect {
        switch annotation.shape {
        case .text(let origin, let string):
            return textBounds(origin: origin, string: string, style: annotation.style)
        case .step(let center, _):
            let radius = annotation.style.fontSize * 0.9
            return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        default:
            return annotation.geometryBounds
        }
    }

    /// Top-left at `origin`; height is `ascent + descent` for one line, stacking by `ascent + descent + leading`
    /// for each following line. Width is the widest line's CoreText optical bounds. Falls back to a rough
    /// `0.6 * fontSize` per character when the font cannot be loaded.
    private static func textBounds(origin: CGPoint, string: String, style: AnnotationStyle) -> CGRect {
        guard !string.isEmpty else { return CGRect(origin: origin, size: .zero) }
        let lines = string.components(separatedBy: "\n")
        guard let font = CoreTypeface.font(style.fontFamily, size: style.fontSize, weight: AnnotationTextWeight.forFamily(style.fontFamily)) else {
            let widest = lines.map { CGFloat($0.count) * 0.6 * style.fontSize }.max() ?? 0
            let lineHeight = style.fontSize * 1.2
            return CGRect(x: origin.x, y: origin.y, width: widest, height: lineHeight * CGFloat(lines.count))
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        var width: CGFloat = 0
        for line in lines {
            // An empty line still occupies a line of vertical space; measure a space so its metrics count.
            let attributed = NSAttributedString(string: line.isEmpty ? " " : line,
                                                attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            var lineAscent: CGFloat = 0
            var lineDescent: CGFloat = 0
            var lineLeading: CGFloat = 0
            _ = CTLineGetTypographicBounds(ctLine, &lineAscent, &lineDescent, &lineLeading)
            ascent = max(ascent, lineAscent)
            descent = max(descent, lineDescent)
            leading = max(leading, lineLeading)
            width = max(width, CTLineGetBoundsWithOptions(ctLine, .useOpticalBounds).width)
        }
        let lineStep = ascent + descent + leading
        let height = (ascent + descent) + lineStep * CGFloat(lines.count - 1)
        return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    }
}

/// Weight used to both measure and draw annotation text: bolder for `.text`/`.display`, lighter for `.mono` so
/// digits stay legible at small sizes. Shared by `AnnotationBounds` and `AnnotationRenderer`.
enum AnnotationTextWeight {
    static func forFamily(_ family: FontFamily) -> CGFloat {
        family == .mono ? 500 : 600
    }
}
