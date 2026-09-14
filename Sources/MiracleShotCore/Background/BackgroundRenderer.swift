import CoreGraphics
import Foundation

/// Composes a screenshot over a `BackgroundPreset`. Pure CoreGraphics so the same path serves the preview, the
/// clipboard and the future editor. Output is sRGB, premultiplied RGBA8.
public enum BackgroundRenderer {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// `scale` converts the preset's point values to pixels: pass the capture's `scaleFactor` so a 2x screenshot
    /// gets 2x padding and keeps its own pixel density.
    public static func render(_ source: CGImage, preset: BackgroundPreset, scale: CGFloat) -> CGImage? {
        let padding = CGFloat(preset.padding) * scale
        let width = Int((CGFloat(source.width) + padding * 2).rounded())
        let height = Int((CGFloat(source.height) + padding * 2).rounded())
        guard let ctx = makeContext(width: width, height: height) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        draw(preset.fill, in: canvas, ctx: ctx)

        let imageRect = CGRect(x: padding, y: padding, width: CGFloat(source.width), height: CGFloat(source.height))
        let radius = min(CGFloat(preset.cornerRadius) * scale, imageRect.width / 2, imageRect.height / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        if let shadow = preset.shadow {
            // CG is y-up: a positive on-screen offset is a negative y here.
            ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(shadow.offsetY) * scale),
                          blur: CGFloat(shadow.blur) * scale,
                          color: CGColor(colorSpace: sRGB, components: [0, 0, 0, CGFloat(shadow.opacity)]))
        }
        // The transparency layer lets the shadow follow the clipped image's own alpha (rounded corners, transparent
        // window corners) instead of an opaque rectangle drawn underneath it.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(source, in: imageRect)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// A rounded tile of the fill alone, for menus and pickers.
    public static func swatch(_ preset: BackgroundPreset, size: Int) -> CGImage? {
        guard let ctx = makeContext(width: size, height: size) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = CGFloat(size) * 0.25
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        draw(preset.fill, in: rect, ctx: ctx)
        return ctx.makeImage()
    }

    // MARK: - Private

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func draw(_ fill: BackgroundPreset.Fill, in rect: CGRect, ctx: CGContext) {
        switch fill {
        case .solid(let color):
            ctx.setFillColor(color.cgColor())
            ctx.fill(rect)
        case .linearGradient(let stops, let angle):
            let colors = stops.map { $0.color.cgColor() } as CFArray
            let locations = stops.map { CGFloat($0.location) }
            guard let gradient = CGGradient(colorsSpace: sRGB, colors: colors, locations: locations) else {
                if let first = stops.first { draw(.solid(color: first.color), in: rect, ctx: ctx) }
                return
            }
            // CSS convention: 0 deg points up, 90 deg points right. In CG's y-up space that is (sin, cos).
            let radians = CGFloat(angle) * .pi / 180
            let direction = CGPoint(x: sin(radians), y: cos(radians))
            // Half the length of the gradient line that exactly covers the rect corner to corner.
            let half = (abs(rect.width * direction.x) + abs(rect.height * direction.y)) / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let start = CGPoint(x: center.x - direction.x * half, y: center.y - direction.y * half)
            let end = CGPoint(x: center.x + direction.x * half, y: center.y + direction.y * half)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }
}
