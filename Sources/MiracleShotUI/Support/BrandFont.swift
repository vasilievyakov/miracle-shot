import AppKit
import CoreText

/// Brand typefaces from the UI resource bundle (variable TTFs, registered once per process). Every accessor falls
/// back to the system font when a face is missing, so a broken bundle degrades to SF instead of crashing.
public enum BrandFont {
    public enum Family: String {
        case text = "Onest"
        case mono = "JetBrains Mono"
        case display = "Geologica"
    }

    /// Onest, chrome text. `weight` is the OpenType wght axis value (400 regular, 500 medium, 600 semibold).
    public static func text(size: CGFloat, weight: CGFloat = 400) -> NSFont { font(.text, size: size, weight: weight) }
    /// JetBrains Mono, sizes, HUD values and every number.
    public static func mono(size: CGFloat, weight: CGFloat = 500) -> NSFont { font(.mono, size: size, weight: weight) }
    /// Geologica, large headings only.
    public static func display(size: CGFloat, weight: CGFloat = 600) -> NSFont { font(.display, size: size, weight: weight) }

    private static let registered: Bool = {
        guard let dir = UIResources.bundle.url(forResource: "fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return false
        }
        var any = false
        for url in files where url.pathExtension.lowercased() == "ttf" {
            // Returns false when the font is already registered (e.g. by a second test bundle); that is still usable.
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { any = true }
        }
        return any
    }()

    /// 'wght' as a four-character tag.
    private static let weightAxis = 0x77676874

    static func font(_ family: Family, size: CGFloat, weight: CGFloat) -> NSFont {
        _ = registered
        let attributes: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family.rawValue,
            kCTFontVariationAttribute: [NSNumber(value: weightAxis): weight],
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
        guard font.familyName == family.rawValue else { return fallback(family, size: size, weight: weight) }
        return font
    }

    private static func fallback(_ family: Family, size: CGFloat, weight: CGFloat) -> NSFont {
        let systemWeight: NSFont.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        switch family {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: systemWeight)
        case .text, .display: return .systemFont(ofSize: size, weight: systemWeight)
        }
    }
}
