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

/// Drop shadow under the screenshot. All values in points; `offsetY` positive moves the shadow down on screen.
public struct BackgroundShadow: Codable, Sendable, Equatable {
    public var blur: Double
    public var offsetY: Double
    /// Black at this opacity, 0...1.
    public var opacity: Double

    public init(blur: Double, offsetY: Double, opacity: Double) {
        self.blur = blur
        self.offsetY = offsetY
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
    /// Space around the screenshot, in points.
    public var padding: Double
    /// Radius applied to the screenshot's corners, in points.
    public var cornerRadius: Double
    public var shadow: BackgroundShadow?

    public init(id: String, name: String, fill: Fill, padding: Double, cornerRadius: Double, shadow: BackgroundShadow?) {
        self.id = id
        self.name = name
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
}
