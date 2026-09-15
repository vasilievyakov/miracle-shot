import CoreGraphics
import Foundation

/// The part of a window that scrolls (an `AXScrollArea` found through Accessibility), in CG global points.
/// Frames of a scrolling capture are cropped to it so sidebars, toolbars and other chrome never reach the
/// stitcher.
public struct ScrollRegion: Sendable, Equatable {
    /// Areas narrower or shorter than this (points) are not worth scrolling: a scrollbar, a text field.
    public static let minimumSide: CGFloat = 64

    /// The region, clipped to the window.
    public let frame: CGRect
    /// The window the region belongs to.
    public let window: CGRect

    public init?(area: CGRect, window: CGRect) {
        let clipped = area.intersection(window)
        guard !clipped.isNull, clipped.width >= Self.minimumSide, clipped.height >= Self.minimumSide else { return nil }
        self.frame = clipped
        self.window = window
    }

    /// The region in the window image's pixels (origin top-left of the window), rounded outwards to whole pixels.
    public func pixelRect(scale: CGFloat) -> CGRect {
        CGRect(x: (frame.minX - window.minX) * scale, y: (frame.minY - window.minY) * scale,
               width: frame.width * scale, height: frame.height * scale).integral
    }

    /// Cuts the region out of a window image captured at `scale`; nil when the image does not cover it.
    public func crop(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let rect = pixelRect(scale: scale)
        guard CGRect(x: 0, y: 0, width: image.width, height: image.height).contains(rect) else { return nil }
        return image.cropping(to: rect)
    }
}
