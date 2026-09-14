import CoreGraphics
import Foundation
import os

/// Composes a screenshot over a `BackgroundPreset`. Pure CoreGraphics so the same path serves the preview, the
/// clipboard and the future editor. Output is sRGB, premultiplied RGBA8.
public enum BackgroundRenderer {
    private static let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "background")
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Stops sampled along a gradient before handing it to `CGGradient`; the samples are OKLab-interpolated so a
    /// two-color ramp does not dip through a muddy midtone the way a raw sRGB blend does.
    private static let gradientSamples = 48
    /// Samples along a glow's radius, alpha falling off by `smoothstep` so the edge is soft, not a hard ring.
    private static let glowSamples = 24

    /// `scale` converts the preset's point values to pixels: pass the capture's `scaleFactor` so a 2x screenshot
    /// gets 2x padding and keeps its own pixel density.
    public static func render(_ source: CGImage, preset: BackgroundPreset, scale: CGFloat) -> CGImage? {
        // Hand-edited presets can carry anything; a NaN would trap in `Int(...)` or empty the clip path silently.
        guard preset.isRenderable, scale.isFinite, scale > 0 else { return nil }
        // Rounded once so both margins are identical at fractional scale factors.
        let padding = (CGFloat(preset.padding) * scale).rounded()
        let width = Int(CGFloat(source.width) + padding * 2)
        let height = Int(CGFloat(source.height) + padding * 2)
        guard let fill = fillImage(preset, width: width, height: height), let ctx = makeContext(width: width, height: height) else {
            return nil
        }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.draw(fill, in: canvas)

        let imageRect = CGRect(x: padding, y: padding, width: CGFloat(source.width), height: CGFloat(source.height))
        let radius = min(CGFloat(preset.cornerRadius) * scale, imageRect.width / 2, imageRect.height / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        if let shadow = preset.shadow, shadow.opacity > 0 {
            // CG is y-up: a positive on-screen offset is a negative y here.
            ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(shadow.offsetY) * scale),
                          blur: CGFloat(shadow.blur) * scale,
                          color: CGColor(colorSpace: sRGB, components: [0, 0, 0, CGFloat(shadow.opacity)]))
            // The transparency layer lets the shadow follow the clipped image's own alpha (rounded corners,
            // transparent window corners) instead of an opaque rectangle drawn underneath it. It costs a
            // canvas-sized buffer, so it is skipped when there is no shadow to compute.
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(source, in: imageRect)
            ctx.endTransparencyLayer()
        } else {
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(source, in: imageRect)
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }

    /// A rounded tile of the fill alone, for menus and pickers.
    public static func swatch(_ preset: BackgroundPreset, size: Int) -> CGImage? {
        guard preset.isRenderable, let fill = fillImage(preset, width: size, height: size), let ctx = makeContext(width: size, height: size) else {
            return nil
        }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let radius = CGFloat(size) * 0.25
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(fill, in: rect)
        return ctx.makeImage()
    }

    // MARK: - Fill (16 bit, OKLab-expanded stops, glows, dithered to 8 bit)

    /// The fill is drawn in 16 bits per channel (base gradient with OKLab-expanded stops, then the glows) and
    /// quantized to 8 bits with triangular dither, so subtle dark ramps do not band and blends stay clean.
    static func fillImage(_ preset: BackgroundPreset, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard let (ctx, format) = makeHighBitDepthContext(width: width, height: height), let data = ctx.data else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        drawBase(preset.fill, in: rect, ctx: ctx)
        for glow in preset.glows {
            drawGlow(glow, in: rect, ctx: ctx)
        }
        return ditheredImage(from: data, bytesPerRow: ctx.bytesPerRow, width: width, height: height, format: format)
    }

    private static func drawBase(_ fill: BackgroundPreset.Fill, in rect: CGRect, ctx: CGContext) {
        switch fill {
        case .solid(let color):
            ctx.setFillColor(color.cgColor())
            ctx.fill(rect)
        case .linearGradient(let stops, let angle):
            guard stops.count > 1 else {
                if let only = stops.first { drawBase(.solid(color: only.color), in: rect, ctx: ctx) }
                return
            }
            let sorted = stops.sorted { $0.location < $1.location }
            var colors: [CGColor] = []
            var locations: [CGFloat] = []
            colors.reserveCapacity(gradientSamples)
            locations.reserveCapacity(gradientSamples)
            for i in 0..<gradientSamples {
                let t = Double(i) / Double(gradientSamples - 1)
                colors.append(sampledColor(sorted, at: t).cgColor())
                locations.append(CGFloat(t))
            }
            guard let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations) else {
                // `isRenderable` guarantees at least one stop, so this only covers CGGradient refusing the input.
                drawBase(.solid(color: sorted[0].color), in: rect, ctx: ctx)
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

    /// OKLab-interpolated color at `t` (0...1) along stops sorted by location; clamped at the ends.
    private static func sampledColor(_ stops: [GradientStop], at t: Double) -> BrandColor {
        guard let first = stops.first, let last = stops.last else { return BrandPalette.ink }
        if t <= first.location { return first.color }
        if t >= last.location { return last.color }
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            guard t >= a.location, t <= b.location else { continue }
            let span = b.location - a.location
            let localT = span > 0 ? (t - a.location) / span : 0
            return OKLab.mix(OKLab.from(a.color), OKLab.from(b.color), localT).toSRGB()
        }
        return last.color
    }

    private static func drawGlow(_ glow: GradientGlow, in rect: CGRect, ctx: CGContext) {
        // Unit coordinates are top-left origin; CG is y-up, so the y axis flips.
        let center = CGPoint(x: CGFloat(glow.x) * rect.width, y: (1 - CGFloat(glow.y)) * rect.height)
        let radius = CGFloat(glow.radius) * hypot(rect.width, rect.height)
        guard radius > 0 else { return }
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        colors.reserveCapacity(glowSamples)
        locations.reserveCapacity(glowSamples)
        for i in 0..<glowSamples {
            let t = Double(i) / Double(glowSamples - 1)
            let alpha = glow.opacity * (1 - smoothstep(t))
            colors.append(glow.color.cgColor(alpha: CGFloat(alpha)))
            locations.append(CGFloat(t))
        }
        guard let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: locations) else { return }
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    private static func smoothstep(_ t: Double) -> Double {
        let c = min(1, max(0, t))
        return c * c * (3 - 2 * c)
    }

    // MARK: - High bit depth context and dithered downsample

    /// Component storage of the intermediate fill context: 16-bit unsigned normalized is the target, with a
    /// 32-bit float fallback for machines where CoreGraphics refuses the 16-bit little-endian format.
    private enum ComponentFormat {
        case uint16
        case float32
    }

    private static func makeHighBitDepthContext(width: Int, height: Int) -> (CGContext, ComponentFormat)? {
        if let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 16, bytesPerRow: 0,
                               space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue) {
            return (ctx, .uint16)
        }
        log.error("16-bit-per-component context refused; falling back to 32-bit float components")
        if let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 32, bytesPerRow: 0, space: sRGB,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            return (ctx, .float32)
        }
        return nil
    }

    /// Reads the high bit depth buffer and writes an 8-bit premultipliedLast image, adding triangular dither so a
    /// subtle ramp does not band into flat steps.
    private static func ditheredImage(from data: UnsafeMutableRawPointer, bytesPerRow: Int, width: Int, height: Int,
                                      format: ComponentFormat) -> CGImage? {
        let bytesPerRow8 = width * 4
        var out = [UInt8](repeating: 0, count: bytesPerRow8 * height)
        out.withUnsafeMutableBytes { outBuffer in
            let outBase = outBuffer.baseAddress!
            for y in 0..<height {
                for x in 0..<width {
                    let dstOffset = y * bytesPerRow8 + x * 4
                    for c in 0..<4 {
                        let noise = ditherNoise(x: x, y: y, channel: c)
                        let level: Double
                        switch format {
                        case .uint16:
                            let srcOffset = y * bytesPerRow + (x * 4 + c) * MemoryLayout<UInt16>.size
                            let v16 = data.load(fromByteOffset: srcOffset, as: UInt16.self)
                            level = Double(v16) / 257 + noise
                        case .float32:
                            let srcOffset = y * bytesPerRow + (x * 4 + c) * MemoryLayout<Float>.size
                            let vf = data.load(fromByteOffset: srcOffset, as: Float.self)
                            level = Double(vf) * 255 + noise
                        }
                        let clamped = max(0, min(255, level.rounded()))
                        outBase.storeBytes(of: UInt8(clamped), toByteOffset: dstOffset + c, as: UInt8.self)
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow8,
                       space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Triangular noise in (-0.5, 0.5): the sum of two independent, deterministic 0..<1 hashes minus 1, halved.
    private static func ditherNoise(x: Int, y: Int, channel: Int) -> Double {
        (hash01(x, y, channel) + hash01(x + 1, y, channel)) / 2 - 0.5
    }

    /// Cheap integer hash, deterministic across runs (tests need no randomness), mapped to 0..<1 via its top bits.
    private static func hash01(_ x: Int, _ y: Int, _ channel: Int) -> Double {
        let ux = UInt32(truncatingIfNeeded: x), uy = UInt32(truncatingIfNeeded: y), uc = UInt32(truncatingIfNeeded: channel)
        var h = ux &* 73_856_093
        h ^= uy &* 19_349_663
        h ^= uc &* 83_492_791
        h = h &* 2_654_435_761
        return Double(h >> 8) / Double(1 << 24)
    }

    // MARK: - Final 8-bit canvas

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

private extension BackgroundPreset {
    /// Finite, non-negative geometry, at least one gradient stop with finite locations, and glows within their
    /// documented ranges.
    var isRenderable: Bool {
        guard padding.isFinite, padding >= 0, cornerRadius.isFinite, cornerRadius >= 0 else { return false }
        if let shadow, !(shadow.blur.isFinite && shadow.blur >= 0 && shadow.offsetY.isFinite && shadow.opacity.isFinite) {
            return false
        }
        switch fill {
        case .solid: break
        case .linearGradient(let stops, let angle):
            guard angle.isFinite, !stops.isEmpty, stops.allSatisfy({ $0.location.isFinite }) else { return false }
        }
        return glows.allSatisfy { glow in
            glow.x.isFinite && (0...1).contains(glow.x) && glow.y.isFinite && (0...1).contains(glow.y)
                && glow.opacity.isFinite && (0...1).contains(glow.opacity) && glow.radius.isFinite && glow.radius > 0
        }
    }
}
