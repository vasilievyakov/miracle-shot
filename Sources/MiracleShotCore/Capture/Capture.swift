import CoreGraphics
import Foundation

/// What the user asked to capture.
public enum CaptureMode: Sendable, Equatable, Hashable {
    case area
    case window
    case fullScreen
}

/// A finished screenshot plus the metadata the rest of the app needs.
public struct Capture: Sendable {
    public let image: CGImage
    public let timestamp: Date
    public let sourceAppName: String?
    public let sourceWindowTitle: String?
    /// Global rect in CoreGraphics coordinates (origin top-left of the primary display), in points.
    public let bounds: CGRect
    public let scaleFactor: CGFloat

    public init(image: CGImage, timestamp: Date = Date(), sourceAppName: String? = nil,
                sourceWindowTitle: String? = nil, bounds: CGRect, scaleFactor: CGFloat) {
        self.image = image
        self.timestamp = timestamp
        self.sourceAppName = sourceAppName
        self.sourceWindowTitle = sourceWindowTitle
        self.bounds = bounds
        self.scaleFactor = scaleFactor
    }

    public var pixelWidth: Int { image.width }
    public var pixelHeight: Int { image.height }
}
