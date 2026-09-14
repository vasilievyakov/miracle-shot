import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class BackgroundRendererTests: XCTestCase {
    private let red = TestImages.RGBA(r: 255, g: 0, b: 0, a: 255)
    private let lime = TestImages.RGBA(r: 0xd4, g: 0xff, b: 0x3f, a: 255)
    private let bone = TestImages.RGBA(r: 0xf3, g: 0xf0, b: 0xe8, a: 255)

    private func preset(fill: BackgroundPreset.Fill, paddingPercent: Double = 10, cornerRadiusPercent: Double = 0,
                        shadow: BackgroundShadow? = nil) -> BackgroundPreset {
        BackgroundPreset(id: "t", name: "T", fill: fill, paddingPercent: paddingPercent, cornerRadiusPercent: cornerRadiusPercent, shadow: shadow)
    }

    private func source(_ w: Int = 20, _ h: Int = 10) -> CGImage {
        TestImages.solid(width: w, height: h, r: 1, g: 0, b: 0)
    }

    func testSolidFillPadsAndKeepsSource() throws {
        // 200x100 source, reference (200+100)/2 = 150. paddingPercent 20 -> 150 * 0.2 = 30 px (above the 24 pt
        // floor) -> canvas 200+60=260 x 100+60=160. Image spans x 30..<230, y 30..<130.
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 100), preset: preset(fill: .solid(color: BrandPalette.lime), paddingPercent: 20), scale: 1))
        XCTAssertEqual(out.width, 260)
        XCTAssertEqual(out.height, 160)
        TestImages.assertClose(TestImages.pixel(out, x: 2, y: 2), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 130, y: 80), red)    // center of the image area
        TestImages.assertClose(TestImages.pixel(out, x: 30, y: 30), red)     // top-left of the image area, no rounding
        TestImages.assertClose(TestImages.pixel(out, x: 229, y: 129), red)   // bottom-right of the image area
    }

    func testCornerRadiusClipsSourceCorners() throws {
        // Same 200x100 source and paddingPercent 20 -> canvas 260x160, image at x 30..<230, y 30..<130 (as above).
        // cornerRadiusPercent 8 -> 150 * 0.08 = 12 px radius (above the 6 pt floor).
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 100), preset: preset(fill: .solid(color: BrandPalette.lime), paddingPercent: 20, cornerRadiusPercent: 8), scale: 1))
        TestImages.assertClose(TestImages.pixel(out, x: 30, y: 30), lime)    // corner is cut away
        TestImages.assertClose(TestImages.pixel(out, x: 130, y: 80), red)    // center intact
        TestImages.assertClose(TestImages.pixel(out, x: 130, y: 30), red)    // top edge midpoint intact
    }

    func testScaleOnlyRaisesTheFloors() throws {
        // 200x100 source, reference 150, paddingPercent 20 -> raw padding 150 * 0.2 = 30 px; this does not depend
        // on scale, only the floor (24 pt * scale) does.
        // scale 1: floor 24 px < 30 px raw, so padding stays 30 -> canvas 260x160 (same as testSolidFillPadsAndKeepsSource).
        let atScale1 = try XCTUnwrap(BackgroundRenderer.render(source(200, 100), preset: preset(fill: .solid(color: BrandPalette.ink), paddingPercent: 20), scale: 1))
        XCTAssertEqual(atScale1.width, 260)
        XCTAssertEqual(atScale1.height, 160)
        // scale 2: floor becomes 24 * 2 = 48 px, which now exceeds the 30 px raw padding, so the floor wins ->
        // canvas 200 + 96 = 296 x 100 + 96 = 196.
        let atScale2 = try XCTUnwrap(BackgroundRenderer.render(source(200, 100), preset: preset(fill: .solid(color: BrandPalette.ink), paddingPercent: 20), scale: 2))
        XCTAssertEqual(atScale2.width, 296)
        XCTAssertEqual(atScale2.height, 196)

        // A tiny 20x10 source (reference 15) makes the floor dominate at every scale: raw = 15 * 0.2 = 3 px.
        // scale 1: floor 24 px -> canvas 20+48=68 x 10+48=58.
        let tinyAtScale1 = try XCTUnwrap(BackgroundRenderer.render(source(20, 10), preset: preset(fill: .solid(color: BrandPalette.ink), paddingPercent: 20), scale: 1))
        XCTAssertEqual(tinyAtScale1.width, 68)
        XCTAssertEqual(tinyAtScale1.height, 58)
        // scale 2: floor 48 px -> canvas 20+96=116 x 10+96=106.
        let tinyAtScale2 = try XCTUnwrap(BackgroundRenderer.render(source(20, 10), preset: preset(fill: .solid(color: BrandPalette.ink), paddingPercent: 20), scale: 2))
        XCTAssertEqual(tinyAtScale2.width, 116)
        XCTAssertEqual(tinyAtScale2.height, 106)
    }

    func testGradientRunsLeftToRightAt90Degrees() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.bone, location: 1)], angle: 90)
        // 200x200 source, reference 200, paddingPercent 150 -> 300 px padding -> canvas 800x800; image at
        // x/y 300..<500, so sampling near the top edge (y small) stays clear of it at every x.
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 200), preset: preset(fill: fill, paddingPercent: 150), scale: 1))
        XCTAssertEqual(out.width, 800)
        let left = TestImages.pixel(out, x: 1, y: 2).r
        let middle = TestImages.pixel(out, x: 400, y: 2).r
        let right = TestImages.pixel(out, x: 798, y: 2).r
        XCTAssertLessThan(left, middle)
        XCTAssertLessThan(middle, right)
        // Same column, different row: unchanged (gradient is horizontal).
        XCTAssertEqual(Int(TestImages.pixel(out, x: 1, y: 797).r), Int(left), accuracy: 2)
    }

    func testGradientRunsBottomToTopAtZeroDegrees() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.bone, location: 1)], angle: 0)
        // Same 200x200 source, paddingPercent 150 -> canvas 800x800 (see above).
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 200), preset: preset(fill: fill, paddingPercent: 150), scale: 1))
        let bottom = TestImages.pixel(out, x: 2, y: 798).r   // y counts from the top
        let top = TestImages.pixel(out, x: 2, y: 1).r
        XCTAssertLessThan(bottom, top)
    }

    func testShadowDarkensBelowTheImage() throws {
        // 200x100 source, paddingPercent 20 -> canvas 260x160, image at x 30..<230, y 30..<130 (as in the padding
        // test above). blurPercent 4, offsetPercent 6 -> reference 150 * 0.04 = 6 px blur, 150 * 0.06 = 9 px offset.
        let shadow = BackgroundShadow(blurPercent: 4, offsetPercent: 6, opacity: 1)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 100), preset: preset(fill: .solid(color: BrandPalette.bone), paddingPercent: 20, shadow: shadow), scale: 1))
        let below = TestImages.pixel(out, x: 130, y: 134)   // 4 px under the image's bottom edge (image spans y 30..<130)
        let above = TestImages.pixel(out, x: 130, y: 18)    // 12 px above the top edge, outside the shadow
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
        let nan = preset(fill: .solid(color: BrandPalette.lime), paddingPercent: .nan)
        XCTAssertNil(BackgroundRenderer.render(source(), preset: nan, scale: 1))
        let negative = preset(fill: .solid(color: BrandPalette.lime), paddingPercent: -4)
        XCTAssertNil(BackgroundRenderer.render(source(), preset: negative, scale: 1))
        let nanRadius = preset(fill: .solid(color: BrandPalette.lime), cornerRadiusPercent: .nan)
        XCTAssertNil(BackgroundRenderer.render(source(), preset: nanRadius, scale: 1))
        let noStops = preset(fill: .linearGradient(stops: [], angle: 0))
        XCTAssertNil(BackgroundRenderer.render(source(), preset: noStops, scale: 1))
        XCTAssertNil(BackgroundRenderer.swatch(noStops, size: 8))
    }

    func testFractionalScaleKeepsMarginsEqual() throws {
        // 200x100 source, reference 150, paddingPercent 15.5 -> raw 150 * 0.155 = 23.25 px; floor 24 * 1.5 = 36 px
        // wins (36 > 23.25) -> canvas 200+72=272 x 100+72=172. Image at x 36..<236, y 36..<136.
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 100), preset: preset(fill: .solid(color: BrandPalette.lime), paddingPercent: 15.5), scale: 1.5))
        XCTAssertEqual(out.width, 272)
        XCTAssertEqual(out.height, 172)
        TestImages.assertClose(TestImages.pixel(out, x: 35, y: 35), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 36, y: 36), red)
        TestImages.assertClose(TestImages.pixel(out, x: 235, y: 135), red)
        TestImages.assertClose(TestImages.pixel(out, x: 236, y: 136), lime)
    }

    func testGradientBlendsPerceptually() throws {
        // Coral to ink2 through sRGB dips into brown; through OKLab the midpoint stays on the straight Lab line.
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.coral, location: 0),
                                                                GradientStop(color: BrandPalette.ink2, location: 1)], angle: 90)
        // 2x2 source, reference 2 -> default paddingPercent 10 gives 0.2 px, far under the 24 pt floor, so padding
        // is 24 px -> canvas 50x50. The assertion samples relative to out.width, so the exact canvas size does not matter.
        let out = try XCTUnwrap(BackgroundRenderer.render(source(2, 2), preset: preset(fill: fill), scale: 1))
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
        // 200x200 source, reference 200, paddingPercent 150 -> 300 px padding -> canvas 800x800; image at
        // x/y 300..<500. The sampled columns (10..<290) and rows (0..<200) below stay well clear of it.
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 200), preset: preset(fill: fill, paddingPercent: 150), scale: 1))
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
        // 2x2 source, reference 2 -> default paddingPercent 10 is far under the 24 pt floor, so padding is 24 px ->
        // canvas 50x50. Both samples below are relative to out.width/out.height, so the exact canvas size does not matter.
        var p = preset(fill: .solid(color: BrandPalette.ink))
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

    func testPaddingIsProportionalToTheCapture() throws {
        // 400x200 source: reference 300, paddingPercent 10 -> 30 px padding -> width 400+60=460.
        let small = try XCTUnwrap(BackgroundRenderer.render(source(400, 200), preset: preset(fill: .solid(color: BrandPalette.lime), paddingPercent: 10), scale: 1))
        XCTAssertEqual(small.width, 460)
        // 4000x2000 source: reference 3000, paddingPercent 10 -> 300 px padding -> width 4000+600=4600. Same
        // percentage, proportionally the same look, at 10x the resolution.
        let large = try XCTUnwrap(BackgroundRenderer.render(source(4000, 2000), preset: preset(fill: .solid(color: BrandPalette.lime), paddingPercent: 10), scale: 1))
        XCTAssertEqual(large.width, 4600)
    }

    /// Neighbouring pixels must not share dither noise: a lag-1 correlation shows up as horizontal streaks.
    func testDitherNoiseIsUncorrelatedBetweenNeighbours() throws {
        let fill = BackgroundPreset.Fill.linearGradient(stops: [GradientStop(color: BrandPalette.ink, location: 0),
                                                                GradientStop(color: BrandPalette.ink2, location: 1)], angle: 90)
        // 200x200 source, paddingPercent 150 -> canvas 800x800, image at x/y 300..<500 (as above).
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 200), preset: preset(fill: fill, paddingPercent: 150), scale: 1))
        // Residual = pixel minus the column mean, so the ramp itself does not count as correlation.
        let width = 200, height = 200
        let red = TestImages.channel(out, 0)
        var residual = [[Double]](repeating: [Double](repeating: 0, count: width), count: height)
        for x in 0..<width {
            let column = (0..<height).map { Double(red[$0][x + 20]) }
            let mean = column.reduce(0, +) / Double(height)
            for y in 0..<height { residual[y][x] = column[y] - mean }
        }
        func correlation(dx: Int, dy: Int) -> Double {
            var num = 0.0, den = 0.0
            for y in 0..<(height - dy) {
                for x in 0..<(width - dx) {
                    num += residual[y][x] * residual[y + dy][x + dx]
                    den += residual[y][x] * residual[y][x]
                }
            }
            return den == 0 ? 0 : num / den
        }
        XCTAssertGreaterThan(correlation(dx: 0, dy: 0), 0.99)
        XCTAssertLessThan(abs(correlation(dx: 1, dy: 0)), 0.1)
        XCTAssertLessThan(abs(correlation(dx: 0, dy: 1)), 0.1)
        XCTAssertLessThan(abs(correlation(dx: 2, dy: 0)), 0.1)
    }

    func testEdgeGlowBrightensEdgesAndCorners() throws {
        // 200x200 source, reference 200, paddingPercent 50 -> 200 * 0.5 = 100 px (above the 24 pt floor) -> canvas
        // 200+200=400 x 400. No frame, so bar = 0 and the band is the whole canvas.
        var p = preset(fill: .solid(color: BrandPalette.ink), paddingPercent: 50)
        p.edgeGlow = EdgeGlow(color: BrandPalette.lime, widthPercent: 20, opacity: 1)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(200, 200), preset: p, scale: 1))
        XCTAssertEqual(out.width, 400)
        XCTAssertEqual(out.height, 400)
        // blur = reference * widthPercent / 100 = 200 * 20 / 100 = 40 px.
        let edge = TestImages.pixel(out, x: 3, y: 200)      // 3 px from the left edge of the band
        let corner = TestImages.pixel(out, x: 3, y: 3)      // 3 px from both the left and top edges
        XCTAssertGreaterThan(Int(edge.g), 60)
        XCTAssertGreaterThan(Int(corner.g), Int(edge.g))
        // 95 px from the left edge, far beyond the 40 px blur (and its 2x inset), so no glow reaches here.
        TestImages.assertClose(TestImages.pixel(out, x: 95, y: 200), TestImages.RGBA(r: 0x0b, g: 0x0b, b: 0x0c, a: 255), tolerance: 4)
    }

    func testBrandFrameAddsBarsAndText() throws {
        // 600x300 source, reference (600+300)/2 = 450. paddingPercent 10 -> 450 * 0.1 = 45 px (above the 24 pt
        // floor). frame barPercent 10 -> 450 * 0.1 = 45 px (above the 36 pt floor). Canvas: width 600+90=690,
        // height 300 (source) + 90 (padding) + 90 (bars) = 480.
        var p = preset(fill: .solid(color: BrandPalette.ink), paddingPercent: 10)
        p.frame = BrandFrame(title: "AI-LAB", tagline: "Agentic Analytics & Research Lab", footer: "ai-lab-agents.com",
                             barPercent: 10, barColor: BrandPalette.ink, titleColor: BrandPalette.lime,
                             textColor: BrandPalette.boneDim, accent: BrandPalette.coral)
        let out = try XCTUnwrap(BackgroundRenderer.render(source(600, 300), preset: p, scale: 1))
        XCTAssertEqual(out.width, 690)
        XCTAssertEqual(out.height, 480)

        let r = TestImages.channel(out, 0)
        let g = TestImages.channel(out, 1)

        // Header band: pixel rows 0..<45 (top of the image; TestImages.pixel/channel count rows from the top).
        var sawLimeTitle = false
        for y in 0..<45 {
            for x in 0..<out.width where g[y][x] > 200 && r[y][x] < 240 {
                sawLimeTitle = true
                break
            }
        }
        XCTAssertTrue(sawLimeTitle, "expected a lime title pixel in the header band")
        // Title starts at x = inset = max(16, 450 * 8 / 100 = 36) = 36, so column 0 is untouched bar color.
        for y in 0..<45 {
            XCTAssertEqual(Int(r[y][0]), 0x0b, accuracy: 2)
            XCTAssertEqual(Int(g[y][0]), 0x0b, accuracy: 2)
        }

        // Footer band: pixel rows 435..<480 (bottom of the image).
        var sawCoral = false
        for y in 435..<480 {
            for x in (out.width * 3 / 4)..<out.width where r[y][x] > 240 && g[y][x] < 120 {
                sawCoral = true
                break
            }
        }
        XCTAssertTrue(sawCoral, "expected a coral accent pixel in the footer's right quarter")

        var sawBoneDim = false
        for y in 435..<480 {
            for x in 0..<(out.width / 2) where (150...200).contains(Int(r[y][x])) && (150...200).contains(Int(g[y][x])) {
                sawBoneDim = true
                break
            }
        }
        XCTAssertTrue(sawBoneDim, "expected a bone-dim footer text pixel in the left half")

        // Picture band: the screenshot at x 45..<645, y (CG) 90..<390, i.e. pixel rows 90..<390. (345, 240) is
        // well inside it.
        TestImages.assertClose(TestImages.pixel(out, x: 345, y: 240), red)
    }
}
