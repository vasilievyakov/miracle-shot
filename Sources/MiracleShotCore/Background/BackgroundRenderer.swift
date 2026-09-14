import CoreGraphics
import CoreText
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
    /// Point floor for padding, so a tiny capture still gets a usable margin; multiplied by `scale` to become
    /// pixels. Applied only when `paddingPercent` is greater than zero (a zero percent means edge-to-edge).
    public static let minimumPadding: CGFloat = 24
    /// Point floor for the corner radius, same rule as `minimumPadding`.
    public static let minimumCornerRadius: CGFloat = 6
    /// Point floor for a brand frame's bar height, multiplied by `scale`.
    public static let minimumBarHeight: CGFloat = 36
    /// Point floor for the frame's text sizes, multiplied by `scale`.
    public static let minimumTextSize: CGFloat = 10
    /// Point floor for the frame's side inset, multiplied by `scale`.
    public static let minimumInset: CGFloat = 16
    private static let presetLog = Logger(subsystem: "agency.blackbloom.miracleshot", category: "presets")

    /// `scale` converts the point-based floors to pixels: pass the capture's `scaleFactor` so a 2x screenshot
    /// keeps its own pixel density. Padding, corner radius and shadow are otherwise a percent of the "reference"
    /// (the mean of the source's width and height, in pixels), so they do not change with `scale` on their own.
    public static func render(_ source: CGImage, preset: BackgroundPreset, scale: CGFloat) -> CGImage? {
        // Hand-edited presets can carry anything; a NaN would trap in `Int(...)` or empty the clip path silently.
        guard preset.isRenderable, scale.isFinite, scale > 0 else { return nil }
        let reference = CGFloat(source.width + source.height) / 2
        // Rounded once so both margins are identical at fractional scale factors. A zero percent means
        // edge-to-edge padding (the floor is skipped so a test can render flush to the canvas).
        let padding: CGFloat = preset.paddingPercent > 0
            ? max(Self.minimumPadding * scale, reference * CGFloat(preset.paddingPercent) / 100).rounded()
            : 0
        // A frame adds ink bars above and below the picture area; their height is a percent of the reference,
        // like every other geometric knob, with its own floor so a tiny capture still gets a legible bar.
        let bar: CGFloat = preset.frame == nil ? 0
            : max(Self.minimumBarHeight * scale, reference * CGFloat(preset.frame!.barPercent) / 100).rounded()
        let width = Int(CGFloat(source.width) + padding * 2)
        let bandHeight = Int(CGFloat(source.height) + padding * 2)
        let height = bandHeight + Int(bar * 2)
        guard let fill = fillImage(preset, width: width, height: bandHeight), let ctx = makeContext(width: width, height: height) else {
            return nil
        }

        // The picture band is the canvas minus the bars, full width; the fill (and the edge glow) live only here,
        // never behind the bars.
        let band = CGRect(x: 0, y: bar, width: CGFloat(width), height: CGFloat(bandHeight))
        ctx.draw(fill, in: band)

        if let edgeGlow = preset.edgeGlow {
            drawEdgeGlow(edgeGlow, band: band, reference: reference, ctx: ctx)
        }

        if let frame = preset.frame {
            drawFrame(frame, bar: bar, width: width, height: height, reference: reference, scale: scale, ctx: ctx)
        }

        let imageRect = CGRect(x: padding, y: bar + padding, width: CGFloat(source.width), height: CGFloat(source.height))
        let rawRadius: CGFloat = preset.cornerRadiusPercent > 0
            ? max(Self.minimumCornerRadius * scale, reference * CGFloat(preset.cornerRadiusPercent) / 100)
            : 0
        let radius = min(rawRadius, imageRect.width / 2, imageRect.height / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        if let shadow = preset.shadow, shadow.opacity > 0 {
            // CG is y-up: a positive on-screen offset is a negative y here. Blur and offset are also a percent of
            // the reference, not scaled by `scale`: the reference is already in pixels.
            ctx.setShadow(offset: CGSize(width: 0, height: -reference * CGFloat(shadow.offsetPercent) / 100),
                          blur: reference * CGFloat(shadow.blurPercent) / 100,
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

    // MARK: - Edge glow and brand frame

    /// Classic CG inner shadow: a ring drawn just outside the picture band casts a blurred shadow that bleeds
    /// inward across the band's edges (and further still in the corners, where two edges overlap); the ring
    /// itself is clipped away by `band`, only its shadow lands inside.
    private static func drawEdgeGlow(_ edge: EdgeGlow, band: CGRect, reference: CGFloat, ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: band)
        let blur = reference * CGFloat(edge.widthPercent) / 100
        ctx.setShadow(offset: .zero, blur: blur, color: edge.color.cgColor(alpha: CGFloat(edge.opacity)))
        let ring = CGMutablePath()
        ring.addRect(band.insetBy(dx: -blur * 2, dy: -blur * 2))
        ring.addRect(band)
        ctx.addPath(ring)
        ctx.setFillColor(edge.color.cgColor())
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    /// Ink bars above and below the picture band, with the title/tagline in the header, the footer text and an
    /// optional accent square in the footer. Bars and the accent square draw regardless of font availability;
    /// only the text is skipped (and logged once) when the brand mono face cannot be loaded.
    private static func drawFrame(_ frame: BrandFrame, bar: CGFloat, width: Int, height: Int, reference: CGFloat, scale: CGFloat, ctx: CGContext) {
        let widthF = CGFloat(width)
        let heightF = CGFloat(height)
        ctx.setFillColor(frame.barColor.cgColor())
        ctx.fill(CGRect(x: 0, y: heightF - bar, width: widthF, height: bar))   // header, top of the canvas
        ctx.fill(CGRect(x: 0, y: 0, width: widthF, height: bar))               // footer, bottom of the canvas

        let titleSize = max(Self.minimumTextSize * scale, reference * 1.0 / 100)
        let smallSize = max(Self.minimumTextSize * scale, reference * 0.8 / 100)
        let inset = max(Self.minimumInset * scale, reference * 8 / 100)
        let headerMidY = heightF - bar / 2
        let footerMidY = bar / 2

        if let titleFont = CoreTypeface.mono(size: titleSize, weight: 700), let bodyFont = CoreTypeface.mono(size: smallSize, weight: 400) {
            ctx.setShouldSmoothFonts(true)
            let titleWidth = drawLine(frame.title, font: titleFont, color: frame.titleColor, x: inset, barMidY: headerMidY, ctx: ctx)
            drawLine(frame.tagline, font: bodyFont, color: frame.textColor, x: inset + titleWidth + 1.5 * smallSize, barMidY: headerMidY, ctx: ctx)
            drawLine(frame.footer, font: bodyFont, color: frame.textColor, x: inset, barMidY: footerMidY, ctx: ctx)
        } else {
            presetLog.error("JetBrains Mono could not be loaded from the resource bundle; drawing the frame without text")
        }

        if let accent = frame.accent {
            let side = max(4 * scale, reference * 0.6 / 100)
            ctx.setFillColor(accent.cgColor())
            ctx.fill(CGRect(x: widthF - inset - side, y: footerMidY - side / 2, width: side, height: side))
        }
    }

    /// Draws one line of text with its baseline vertically centered in a bar; returns the line's typographic
    /// width so a caller can lay out the next run after it.
    @discardableResult
    private static func drawLine(_ text: String, font: CTFont, color: BrandColor, x: CGFloat, barMidY: CGFloat, ctx: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color.cgColor(),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        ctx.textPosition = CGPoint(x: x, y: barMidY - (ascent - descent) / 2)
        CTLineDraw(line, ctx)
        return width
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
                    // The fill is opaque; alpha is written directly instead of going through the dither.
                    outBase.storeBytes(of: UInt8(255), toByteOffset: dstOffset + 3, as: UInt8.self)
                    for c in 0..<3 {
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

    /// Triangular noise in (-0.5, 0.5): the mean of two independent 0..<1 hashes of the same pixel minus a half.
    /// Both hashes take the same coordinates with different salts; sharing a neighbour's hash instead would
    /// correlate adjacent pixels and show as horizontal streaks.
    private static func ditherNoise(x: Int, y: Int, channel: Int) -> Double {
        (hash01(x, y, channel, salt: 0xA511_E9B3) + hash01(x, y, channel, salt: 0x27D4_EB2F)) / 2 - 0.5
    }

    /// Cheap integer hash, deterministic across runs (tests need no randomness), mapped to 0..<1 via its top bits.
    private static func hash01(_ x: Int, _ y: Int, _ channel: Int, salt: UInt32) -> Double {
        let ux = UInt32(truncatingIfNeeded: x), uy = UInt32(truncatingIfNeeded: y), uc = UInt32(truncatingIfNeeded: channel)
        var h = (ux &+ salt) &* 73_856_093
        h ^= (uy ^ salt) &* 19_349_663
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
        guard paddingPercent.isFinite, paddingPercent >= 0, cornerRadiusPercent.isFinite, cornerRadiusPercent >= 0 else { return false }
        if let shadow, !(shadow.blurPercent.isFinite && shadow.blurPercent >= 0 && shadow.offsetPercent.isFinite && shadow.opacity.isFinite) {
            return false
        }
        if let edgeGlow, !(edgeGlow.widthPercent.isFinite && edgeGlow.widthPercent >= 0 && edgeGlow.opacity.isFinite && (0...1).contains(edgeGlow.opacity)) {
            return false
        }
        if let frame, !(frame.barPercent.isFinite && frame.barPercent >= 0) {
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
