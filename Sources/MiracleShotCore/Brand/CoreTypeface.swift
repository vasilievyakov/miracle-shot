import CoreText
import Foundation

/// The brand mono face for rendered text in Core (`BackgroundRenderer`), loaded straight from the resource
/// bundle. No caching: CoreText types are not Sendable, and a render is one call per click.
public enum CoreTypeface {
    /// 'wght' as a four-character tag.
    private static let weightAxis = 0x77676874

    /// JetBrains Mono at `size`, with the variable `wght` axis set to `weight`. `nil` when the bundled file is
    /// missing; the renderer then skips text but still draws the bars.
    public static func mono(size: CGFloat, weight: CGFloat) -> CTFont? {
        guard let dir = CoreResources.bundle.url(forResource: "fonts", withExtension: nil) else { return nil }
        let url = dir.appendingPathComponent("JetBrainsMono-Variable.ttf")
        guard FileManager.default.fileExists(atPath: url.path),
              let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else {
            return nil
        }
        let varied = CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: weightAxis), weight)
        return CTFontCreateWithFontDescriptor(varied, size, nil)
    }
}
