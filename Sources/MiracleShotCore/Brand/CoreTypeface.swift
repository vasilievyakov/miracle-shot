import CoreText
import Foundation

/// Loads a bundled variable font and sets its `wght` axis. No caching: CoreText types are not Sendable, and a
/// render is one call per click.
public enum CoreTypeface {
    /// 'wght' as a four-character tag.
    private static let weightAxis = 0x77676874

    private static func fileName(for family: FontFamily) -> String {
        switch family {
        case .text: return "Onest-Variable.ttf"
        case .mono: return "JetBrainsMono-Variable.ttf"
        case .display: return "Geologica-Variable.ttf"
        }
    }

    /// `family` at `size`, with the variable `wght` axis set to `weight`. `nil` when the bundled file is
    /// missing; callers then skip the text they were about to draw or measure.
    public static func font(_ family: FontFamily, size: CGFloat, weight: CGFloat) -> CTFont? {
        guard let dir = CoreResources.bundle.url(forResource: "fonts", withExtension: nil) else { return nil }
        let url = dir.appendingPathComponent(fileName(for: family))
        guard FileManager.default.fileExists(atPath: url.path),
              let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else {
            return nil
        }
        let varied = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: weightAxis), weight)
        return CTFontCreateWithFontDescriptor(varied, size, nil)
    }

    /// JetBrains Mono at `size`, with the variable `wght` axis set to `weight`. Thin wrapper over
    /// `font(_:size:weight:)` kept for the existing `BackgroundRenderer` call sites.
    public static func mono(size: CGFloat, weight: CGFloat) -> CTFont? {
        font(.mono, size: size, weight: weight)
    }
}
