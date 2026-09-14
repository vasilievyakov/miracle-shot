import AppKit
import CoreText
import MiracleShotCore
import os

/// Brand typefaces from the Core resource bundle (variable TTFs, registered once per process). Every accessor falls
/// back to the system font when a face is missing, so a broken bundle degrades to SF instead of crashing.
/// Main-actor only: the cached CoreText descriptors are not Sendable, and every caller is a view anyway.
@MainActor
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

    private static let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "fonts")

    /// 'wght' as a four-character tag.
    private static let weightAxis = 0x77676874

    /// One descriptor per bundled face. Built from the file itself, so a same-named font installed on the machine
    /// (often a static cut without the weight axis) cannot shadow the bundled one the way a family-name lookup would.
    private static let descriptors: [Family: CTFontDescriptor] = {
        guard let dir = CoreResources.bundle.url(forResource: "fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var result: [Family: CTFontDescriptor] = [:]
        for url in files where url.pathExtension.lowercased() == "ttf" {
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
               let error = error?.takeRetainedValue(),
               CFErrorGetCode(error) != CTFontManagerError.alreadyRegistered.rawValue {
                log.error("Font \(url.lastPathComponent, privacy: .public) not registered: \(String(describing: error), privacy: .public)")
                continue
            }
            guard let descriptor = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first,
                  let familyName = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                  let family = Family(rawValue: familyName) else {
                log.error("Font \(url.lastPathComponent, privacy: .public) is not one of the brand families")
                continue
            }
            result[family] = descriptor
        }
        return result
    }()

    private static func font(_ family: Family, size: CGFloat, weight: CGFloat) -> NSFont {
        guard let base = descriptors[family] else { return fallback(family, size: size, weight: weight) }
        let descriptor = CTFontDescriptorCreateCopyWithVariation(base, NSNumber(value: weightAxis), weight)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    private static func fallback(_ family: Family, size: CGFloat, weight: CGFloat) -> NSFont {
        let systemWeight: NSFont.Weight = weight >= 700 ? .bold : weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        switch family {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: systemWeight)
        case .text, .display: return .systemFont(ofSize: size, weight: systemWeight)
        }
    }
}
