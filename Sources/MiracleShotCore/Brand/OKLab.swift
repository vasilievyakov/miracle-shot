import CoreGraphics
import Foundation

/// Bjorn Ottosson's OKLab: a perceptual space where straight-line blends stay clean (no gray or brown dip
/// halfway between two saturated colors). Used only to build gradient stops; storage stays sRGB.
public struct OKLab: Sendable, Equatable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    public static func from(_ color: BrandColor) -> OKLab {
        let r = linear(color.red), g = linear(color.green), bl = linear(color.blue)
        let l_ = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m_ = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s_ = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        return OKLab(l: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                     a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                     b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    /// Back to gamma-encoded sRGB, clamped to the gamut.
    public func toSRGB() -> BrandColor {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let l3 = l_ * l_ * l_, m3 = m_ * m_ * m_, s3 = s_ * s_ * s_
        let r = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
        let g = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
        let bl = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        return BrandColor(red: gamma(r), green: gamma(g), blue: gamma(bl))
    }

    public static func mix(_ x: OKLab, _ y: OKLab, _ t: Double) -> OKLab {
        OKLab(l: x.l + (y.l - x.l) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }

    // MARK: - sRGB transfer function

    private static func linear(_ c: CGFloat) -> Double {
        let v = Double(c)
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private func gamma(_ v: Double) -> CGFloat {
        let c = min(1, max(0, v))
        return CGFloat(c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055)
    }
}
