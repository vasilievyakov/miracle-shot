import CoreGraphics

/// Zoom state of the editor canvas. Scales are view points per image pixel; `natural` (1 / scaleFactor)
/// shows a Retina capture at its on-screen size and is what the percent labels are relative to.
public enum EditorZoom: Sendable, Equatable {
    case fit
    case fixed(CGFloat)

    /// Multiples of the natural scale offered by zoom in / zoom out.
    public static let presets: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4]

    /// Fit: the largest scale (<= natural) showing the whole image inside `viewSize` minus `padding`; when that
    /// would be less than half of the width-only fit (a scrolling capture), fit the width and let it scroll,
    /// and symmetrically for very wide images. Fixed: the scale clamped to presets.first...presets.last times natural.
    public func scale(imageSize: CGSize, viewSize: CGSize, padding: CGFloat, natural: CGFloat) -> CGFloat {
        switch self {
        case .fit:
            return Self.fitScale(imageSize: imageSize, viewSize: viewSize, padding: padding, natural: natural)
        case .fixed(let scale):
            return Self.clamped(scale, natural: natural)
        }
    }

    private static func fitScale(imageSize: CGSize, viewSize: CGSize, padding: CGFloat, natural: CGFloat) -> CGFloat {
        let availableWidth = viewSize.width - 2 * padding
        let availableHeight = viewSize.height - 2 * padding
        guard imageSize.width > 0, imageSize.height > 0, availableWidth > 0, availableHeight > 0 else {
            return natural
        }
        let widthFit = availableWidth / imageSize.width
        let heightFit = availableHeight / imageSize.height
        let scale: CGFloat
        if heightFit < widthFit / 2 {
            scale = widthFit
        } else if widthFit < heightFit / 2 {
            scale = heightFit
        } else {
            scale = min(widthFit, heightFit)
        }
        return min(scale, natural)
    }

    private static func clamped(_ scale: CGFloat, natural: CGFloat) -> CGFloat {
        min(max(scale, presets.first! * natural), presets.last! * natural)
    }

    /// Next preset strictly above `currentScale` (in units of `natural`); at the top preset, the scale is unchanged.
    public func zoomedIn(currentScale: CGFloat, natural: CGFloat) -> EditorZoom {
        guard natural > 0, let next = Self.presets.first(where: { $0 * natural > currentScale }) else {
            return .fixed(currentScale)
        }
        return .fixed(next * natural)
    }

    /// Next preset strictly below `currentScale`; at the bottom preset, the scale is unchanged.
    public func zoomedOut(currentScale: CGFloat, natural: CGFloat) -> EditorZoom {
        guard natural > 0, let next = Self.presets.last(where: { $0 * natural < currentScale }) else {
            return .fixed(currentScale)
        }
        return .fixed(next * natural)
    }

    /// `.fixed(currentScale * factor)`, clamped (pinch and cmd+wheel).
    public static func scaled(currentScale: CGFloat, by factor: CGFloat, natural: CGFloat) -> EditorZoom {
        .fixed(clamped(currentScale * factor, natural: natural))
    }

    /// "100%", "37%" relative to natural.
    public static func label(scale: CGFloat, natural: CGFloat) -> String {
        guard natural > 0 else { return "100%" }
        return "\(Int((scale / natural * 100).rounded()))%"
    }
}
