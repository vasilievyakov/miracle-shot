import CoreGraphics
import Foundation

/// Opacity and scale of a pinned screenshot, clamped so it can never vanish or explode.
public struct PinTransform: Sendable, Equatable {
    public static let opacityRange: ClosedRange<CGFloat> = 0.2...1.0
    public static let scaleRange: ClosedRange<CGFloat> = 0.25...4.0
    public static let opacityStep: CGFloat = 0.1
    /// Multiplicative step for keyboard zoom.
    public static let scaleStep: CGFloat = 1.25
    /// Multiplicative step per wheel line.
    public static let wheelScaleStep: CGFloat = 1.05

    public var opacity: CGFloat {
        didSet {
            let clamped = min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
            if clamped != opacity { opacity = clamped }
        }
    }

    public var scale: CGFloat {
        didSet {
            let clamped = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
            if clamped != scale { scale = clamped }
        }
    }

    public init(opacity: CGFloat = 1, scale: CGFloat = 1) {
        self.opacity = min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        self.scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    public func opacityIncreased() -> PinTransform {
        var t = self
        t.opacity += Self.opacityStep
        return t
    }

    public func opacityDecreased() -> PinTransform {
        var t = self
        t.opacity -= Self.opacityStep
        return t
    }

    public func scaledUp(by factor: CGFloat = scaleStep) -> PinTransform {
        var t = self
        t.scale *= factor
        return t
    }

    public func scaledDown(by factor: CGFloat = scaleStep) -> PinTransform {
        var t = self
        t.scale /= factor
        return t
    }

    /// Wheel delta in lines (positive = zoom in); each line multiplies by `wheelScaleStep`.
    public func wheeled(lines: CGFloat) -> PinTransform {
        var t = self
        t.scale *= pow(Self.wheelScaleStep, lines)
        return t
    }

    public static let identity = PinTransform()

    /// "100 %" / "80 %" style labels for the HUD.
    public var scaleLabel: String { "\(Int((scale * 100).rounded())) %" }
    public var opacityLabel: String { "\(Int((opacity * 100).rounded())) %" }
}
