import CoreGraphics

/// sRGB color with 0...1 components. The only place hex literals are allowed is `BrandPalette`.
public struct BrandColor: Sendable, Equatable, Hashable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var s = Substring(hex)
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255)
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: Self.sRGB, components: [red, green, blue, alpha])!
    }
}

/// Agentic Lab design tokens. Source of truth: ~/.claude/scripts/lab-brand.py.
public enum BrandPalette {
    /// Panel and frame background.
    public static let ink = BrandColor(hex: "#0b0b0c")!
    /// Raised plate, inset.
    public static let ink2 = BrandColor(hex: "#141416")!
    /// Nested block, code field.
    public static let ink3 = BrandColor(hex: "#1c1c1f")!
    /// Primary text.
    public static let bone = BrandColor(hex: "#f3f0e8")!
    /// Secondary text.
    public static let boneDim = BrandColor(hex: "#b8b4a8")!
    /// Service captions.
    public static let boneFaint = BrandColor(hex: "#6f6c63")!
    /// The accent. Exactly one place per screen.
    public static let lime = BrandColor(hex: "#d4ff3f")!
    /// Muted accent, "was" state.
    public static let limeDim = BrandColor(hex: "#9bbf2a")!
    /// Failure only: error, denied permission.
    public static let coral = BrandColor(hex: "#ff5a36")!
    /// Separators and borders.
    public static let line = BrandColor(hex: "#2a2a2d")!

    /// Selection overlay dimming, black at 35 percent.
    public static let overlayDim = BrandColor(red: 0, green: 0, blue: 0)
    public static let overlayDimAlpha: CGFloat = 0.35

    /// Every token, for tests that enforce "palette only".
    public static let all: [BrandColor] = [ink, ink2, ink3, bone, boneDim, boneFaint, lime, limeDim, coral, line]
}

/// Encoded as a "#rrggbb" string so preset JSON stays readable.
extension BrandColor: Codable {
    public init(from decoder: Decoder) throws {
        let hex = try decoder.singleValueContainer().decode(String.self)
        guard let color = BrandColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "Not a #rrggbb color: \(hex)")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
