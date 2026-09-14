import Foundation

/// One color stop of a gradient; `location` is 0...1 along the gradient line.
public struct GradientStop: Codable, Sendable, Equatable {
    public var color: BrandColor
    public var location: Double

    public init(color: BrandColor, location: Double) {
        self.color = color
        self.location = location
    }
}

/// A soft radial spot of one palette color over the base fill; a few of them give the layered "mesh" look.
public struct GradientGlow: Codable, Sendable, Equatable {
    public var color: BrandColor
    /// Center in unit canvas coordinates: (0, 0) top-left, (1, 1) bottom-right.
    public var x: Double
    public var y: Double
    /// Radius as a fraction of the canvas diagonal.
    public var radius: Double
    /// Opacity at the center, fading to zero at the radius.
    public var opacity: Double

    public init(color: BrandColor, x: Double, y: Double, radius: Double, opacity: Double) {
        self.color = color
        self.x = x
        self.y = y
        self.radius = radius
        self.opacity = opacity
    }
}

/// Drop shadow under the screenshot. `blurPercent` and `offsetPercent` are percent of the mean side of the
/// screenshot (the "reference"); `offsetPercent` positive moves the shadow down on screen.
public struct BackgroundShadow: Codable, Sendable, Equatable {
    public var blurPercent: Double
    public var offsetPercent: Double
    /// Black at this opacity, 0...1.
    public var opacity: Double

    public init(blurPercent: Double, offsetPercent: Double, opacity: Double) {
        self.blurPercent = blurPercent
        self.offsetPercent = offsetPercent
        self.opacity = opacity
    }
}

/// A backdrop the screenshot is placed on. JSON files in `Resources/presets` (built-in) and the user's
/// Application Support `presets` folder. Synthesized `Codable`: the fill reads as
/// `{"solid":{"color":"#..."}}` or `{"linearGradient":{"stops":[...],"angle":135}}`.
public struct BackgroundPreset: Codable, Sendable, Equatable, Identifiable {
    public enum Fill: Codable, Sendable, Equatable {
        case solid(color: BrandColor)
        /// `angle` in degrees, CSS convention: 0 runs bottom to top, 90 left to right, 180 top to bottom.
        case linearGradient(stops: [GradientStop], angle: Double)

        public var colors: [BrandColor] {
            switch self {
            case .solid(let color): return [color]
            case .linearGradient(let stops, _): return stops.map(\.color)
            }
        }
    }

    public var id: String
    public var name: String
    public var fill: Fill
    /// Space around the screenshot, as a percent of the mean side of the screenshot (the source's width and
    /// height, averaged, in pixels).
    public var paddingPercent: Double
    /// Radius applied to the screenshot's corners, as a percent of the mean side of the screenshot.
    public var cornerRadiusPercent: Double
    public var shadow: BackgroundShadow?
    /// Radial spots layered over the base fill. Defaults to none; optional in JSON.
    public var glows: [GradientGlow]

    /// Every palette color this preset uses, fill and glows together, for tests that enforce "palette only".
    public var colors: [BrandColor] {
        fill.colors + glows.map(\.color)
    }

    public init(id: String, name: String, fill: Fill, paddingPercent: Double, cornerRadiusPercent: Double, shadow: BackgroundShadow?,
                glows: [GradientGlow] = []) {
        self.id = id
        self.name = name
        self.fill = fill
        self.paddingPercent = paddingPercent
        self.cornerRadiusPercent = cornerRadiusPercent
        self.shadow = shadow
        self.glows = glows
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, fill, paddingPercent, cornerRadiusPercent, shadow, glows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fill = try container.decode(Fill.self, forKey: .fill)
        paddingPercent = try container.decode(Double.self, forKey: .paddingPercent)
        cornerRadiusPercent = try container.decode(Double.self, forKey: .cornerRadiusPercent)
        shadow = try container.decodeIfPresent(BackgroundShadow.self, forKey: .shadow)
        glows = try container.decodeIfPresent([GradientGlow].self, forKey: .glows) ?? []
    }
}
