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
}
