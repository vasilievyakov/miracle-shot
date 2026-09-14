import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class BackgroundRendererTests: XCTestCase {
    private let red = TestImages.RGBA(r: 255, g: 0, b: 0, a: 255)
    private let lime = TestImages.RGBA(r: 0xd4, g: 0xff, b: 0x3f, a: 255)
    private let bone = TestImages.RGBA(r: 0xf3, g: 0xf0, b: 0xe8, a: 255)

    private func preset(fill: BackgroundPreset.Fill, padding: Double = 10, radius: Double = 0,
                        shadow: BackgroundShadow? = nil) -> BackgroundPreset {
        BackgroundPreset(id: "t", name: "T", fill: fill, padding: padding, cornerRadius: radius, shadow: shadow)
    }

    private func source(_ w: Int = 20, _ h: Int = 10) -> CGImage {
        TestImages.solid(width: w, height: h, r: 1, g: 0, b: 0)
    }

    func testSolidFillPadsAndKeepsSource() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.lime)), scale: 1))
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(out.height, 30)
        TestImages.assertClose(TestImages.pixel(out, x: 2, y: 2), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 15), red)
        TestImages.assertClose(TestImages.pixel(out, x: 10, y: 10), red)   // top-left of the image area, no rounding
        TestImages.assertClose(TestImages.pixel(out, x: 29, y: 19), red)   // bottom-right of the image area
    }

    func testCornerRadiusClipsSourceCorners() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.lime), radius: 6), scale: 1))
        TestImages.assertClose(TestImages.pixel(out, x: 10, y: 10), lime)  // corner is cut away
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 15), red)   // center intact
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 10), red)   // top edge midpoint intact
    }

    func testScaleMultipliesPointValues() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.ink)), scale: 2))
        XCTAssertEqual(out.width, 20 + 40)
        XCTAssertEqual(out.height, 10 + 40)
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 20), red)
    }

    func testGradientRunsLeftToRightAt90Degrees() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.bone, location: 1)], angle: 90)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 20), scale: 1))
        XCTAssertEqual(out.width, 42)
        let left = TestImages.pixel(out, x: 1, y: 2).r
        let middle = TestImages.pixel(out, x: 21, y: 2).r
        let right = TestImages.pixel(out, x: 40, y: 2).r
        XCTAssertLessThan(left, middle)
        XCTAssertLessThan(middle, right)
        // Same column, different row: unchanged (gradient is horizontal).
        XCTAssertEqual(Int(TestImages.pixel(out, x: 1, y: 39).r), Int(left), accuracy: 2)
    }

    func testGradientRunsBottomToTopAtZeroDegrees() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.bone, location: 1)], angle: 0)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 20), scale: 1))
        let bottom = TestImages.pixel(out, x: 2, y: 40).r   // y counts from the top
        let top = TestImages.pixel(out, x: 2, y: 1).r
        XCTAssertLessThan(bottom, top)
    }

    func testShadowDarkensBelowTheImage() throws {
        let shadow = BackgroundShadow(blur: 4, offsetY: 6, opacity: 1)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(10, 10), preset: preset(fill: .solid(color: BrandPalette.bone), padding: 20, shadow: shadow), scale: 1))
        let below = TestImages.pixel(out, x: 25, y: 32)   // 2 px under the image's bottom edge (image spans y 20..<30)
        let above = TestImages.pixel(out, x: 25, y: 12)   // 8 px above the top edge, outside the shadow
        XCTAssertLessThan(below.r, bone.r - 20)
        TestImages.assertClose(above, bone, tolerance: 3)
        TestImages.assertClose(TestImages.pixel(out, x: 2, y: 2), bone, tolerance: 3)
    }

    func testSwatchHasRequestedSizeAndFill() throws {
        let out = try XCTUnwrap(BackgroundRenderer.swatch(preset(fill: .solid(color: BrandPalette.lime)), size: 16))
        XCTAssertEqual(out.width, 16)
        XCTAssertEqual(out.height, 16)
        TestImages.assertClose(TestImages.pixel(out, x: 8, y: 8), lime)
        XCTAssertEqual(TestImages.pixel(out, x: 0, y: 0).a, 0)   // rounded corner is transparent
    }

    func testUnrenderablePresetsReturnNil() {
        let nan = preset(fill: .solid(color: BrandPalette.lime), padding: .nan)
        XCTAssertNil(BackgroundRenderer.render(source(), preset: nan, scale: 1))
        let negative = preset(fill: .solid(color: BrandPalette.lime), padding: -4)
        XCTAssertNil(BackgroundRenderer.render(source(), preset: negative, scale: 1))
        let nanRadius = preset(fill: .solid(color: BrandPalette.lime), radius: .nan)
        XCTAssertNil(BackgroundRenderer.render(source(), preset: nanRadius, scale: 1))
        let noStops = preset(fill: .linearGradient(stops: [], angle: 0))
        XCTAssertNil(BackgroundRenderer.render(source(), preset: noStops, scale: 1))
        XCTAssertNil(BackgroundRenderer.swatch(noStops, size: 8))
    }

    func testFractionalScaleKeepsMarginsEqual() throws {
        let out = try XCTUnwrap(BackgroundRenderer.render(source(), preset: preset(fill: .solid(color: BrandPalette.lime), padding: 3), scale: 1.5))
        // 3 * 1.5 = 4.5 rounds away from zero to 5 px on every side.
        XCTAssertEqual(out.width, 20 + 10)
        TestImages.assertClose(TestImages.pixel(out, x: 4, y: 4), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 5, y: 5), red)
        TestImages.assertClose(TestImages.pixel(out, x: 24, y: 14), red)
        TestImages.assertClose(TestImages.pixel(out, x: 25, y: 15), lime)
    }

    func testGradientBlendsPerceptually() throws {
        // Coral to ink2 through sRGB dips into brown; through OKLab the midpoint stays on the straight Lab line.
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.coral, location: 0),
                                                                GradientStop(color: BrandPalette.ink2, location: 1)], angle: 90)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 100), scale: 1))
        let p = TestImages.pixel(out, x: out.width / 2, y: 5)
        let got = OKLab.from(BrandColor(red: CGFloat(p.r) / 255, green: CGFloat(p.g) / 255, blue: CGFloat(p.b) / 255))
        let want = OKLab.mix(OKLab.from(BrandPalette.coral), OKLab.from(BrandPalette.ink2), 0.5)
        XCTAssertEqual(got.l, want.l, accuracy: 0.02)
        XCTAssertEqual(got.a, want.a, accuracy: 0.02)
        XCTAssertEqual(got.b, want.b, accuracy: 0.02)
    }

    func testSubtleDarkGradientIsDitheredNotBanded() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.ink2, location: 1)], angle: 90)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill, padding: 300), scale: 1))
        // A horizontal ramp of 9 levels over 600 px: without dither every column is one flat value.
        var columnsWithNoise = 0
        for x in stride(from: 10, to: 290, by: 20) {
            let values = Set((0..<200).map { TestImages.pixel(out, x: x, y: $0).r })
            XCTAssertLessThanOrEqual(values.count, 3, "dither must stay within one level")
            if values.count >= 2 { columnsWithNoise += 1 }
        }
        XCTAssertGreaterThanOrEqual(columnsWithNoise, 8)
        // The ramp still runs left to right on average.
        func mean(_ x: Int) -> Double { (0..<200).map { Double(TestImages.pixel(out, x: x, y: $0).r) }.reduce(0, +) / 200 }
        XCTAssertLessThan(mean(20), mean(280))
    }

    func testGlowBrightensAroundItsCenter() throws {
        let glow = GradientGlow(color: BrandPalette.lime, x: 0.2, y: 0.2, radius: 0.3, opacity: 1)
        var p = preset(fill: .solid(color: BrandPalette.ink), padding: 100)
        p.glows = [glow]
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: p, scale: 1))
        let near = TestImages.pixel(out, x: Int(0.2 * Double(out.width)), y: Int(0.2 * Double(out.height)))
        let far = TestImages.pixel(out, x: out.width - 5, y: out.height - 5)
        XCTAssertGreaterThan(near.g, 200)
        TestImages.assertClose(far, TestImages.RGBA(r: 0x0b, g: 0x0b, b: 0x0c, a: 255), tolerance: 2)
    }

    func testUnrenderableGlowReturnsNil() {
        var p = preset(fill: .solid(color: BrandPalette.ink))
        p.glows = [GradientGlow(color: BrandPalette.lime, x: 2, y: 0, radius: 0.3, opacity: 1)]
        XCTAssertNil(BackgroundRenderer.render(source(), preset: p, scale: 1))
    }
}
