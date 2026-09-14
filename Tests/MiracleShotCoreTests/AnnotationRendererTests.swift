import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class AnnotationRendererTests: XCTestCase {
    private let ink = TestImages.RGBA(r: 0x0b, g: 0x0b, b: 0x0c, a: 255)
    private let lime = TestImages.RGBA(r: 0xd4, g: 0xff, b: 0x3f, a: 255)
    private let coral = TestImages.RGBA(r: 0xff, g: 0x5a, b: 0x36, a: 255)
    private let bone = TestImages.RGBA(r: 0xf3, g: 0xf0, b: 0xe8, a: 255)

    private func solidSource(_ color: BrandColor, width: Int = 100, height: Int = 100) -> CGImage {
        TestImages.solid(width: width, height: height, r: color.red, g: color.green, b: color.blue)
    }

    /// Alternating `square`-sized tiles of `a` and `b`, sharp edges everywhere: good raw material for a blur or
    /// pixelate test since any smoothing is easy to detect.
    private func checkerboard(width: Int, height: Int, square: Int, a: BrandColor, b: BrandColor) -> CGImage {
        let ctx = TestImages.context(width: width, height: height)
        for y in stride(from: 0, to: height, by: square) {
            for x in stride(from: 0, to: width, by: square) {
                let isA = ((x / square) + (y / square)) % 2 == 0
                ctx.setFillColor((isA ? a : b).cgColor())
                ctx.fill(CGRect(x: x, y: y, width: square, height: square))
            }
        }
        return ctx.makeImage()!
    }

    private func variance(_ image: CGImage, region: CGRect, channel: Int) -> Double {
        let rows = TestImages.channel(image, channel)
        var values: [Double] = []
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                values.append(Double(rows[y][x]))
            }
        }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    // Rect (20,20,40,40) fill lime, stroke coral, width 4: the stroke is inset by half the line width (2), so
    // its centerline sits at x=22 and, at 4px wide, covers x in [20,24]. (40,40) is deep inside the fill;
    // (21,40) sits on that left stroke edge; (10,10) is outside the rect entirely.
    func testRectFillAndStroke() throws {
        let style = AnnotationStyle(strokeColor: BrandPalette.coral, fillColor: BrandPalette.lime, lineWidth: 4)
        let annotation = Annotation(shape: .rect(CGRect(x: 20, y: 20, width: 40, height: 40)), style: style)
        let document = Document(source: solidSource(BrandPalette.ink), scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        TestImages.assertClose(TestImages.pixel(out, x: 40, y: 40), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 21, y: 40), coral)
        TestImages.assertClose(TestImages.pixel(out, x: 10, y: 10), ink)
    }

    // Crop (50,50,50,50) makes a 50x50 output; a rect at full-image (60,60,20,20) covers full-image x/y 60..<80.
    // Output (20,20) is full-image (70,70) -- inside the rect. Output (5,5) is full-image (55,55) -- outside it.
    func testCropMovesAnnotationsWithTheImage() throws {
        let style = AnnotationStyle(strokeColor: BrandPalette.lime, fillColor: BrandPalette.lime, lineWidth: 4)
        let annotation = Annotation(shape: .rect(CGRect(x: 60, y: 60, width: 20, height: 20)), style: style)
        let document = Document(source: solidSource(BrandPalette.ink), scaleFactor: 1, annotations: [annotation],
                                cropRect: CGRect(x: 50, y: 50, width: 50, height: 50))
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        XCTAssertEqual(out.width, 50)
        XCTAssertEqual(out.height, 50)
        TestImages.assertClose(TestImages.pixel(out, x: 20, y: 20), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 5, y: 5), ink)
    }

    // Arrow (10,50)->(90,50), lime, width 4: headLength = max(12, 4*4) = 16, half-angle 28 degrees, so the head
    // triangle's base sits at axial distance 16*cos(28deg) = 14.13 behind the tip (x = 75.87), with half-width
    // d*tan(28deg) at axial distance d from the tip. (85,50) is on the centerline near the tip (d=5, half-width
    // 2.66, offset 0). (78,54) is at d=12 (half-width 6.38, offset 4) and (82,47) at d=8 (half-width 4.25, offset
    // 3): both comfortably inside the triangle, off its centerline. (50,58) is outside the shaft (half-width 2)
    // and far from the head.
    func testArrowHeadFillsAtTheTip() throws {
        let style = AnnotationStyle(strokeColor: BrandPalette.lime, lineWidth: 4)
        let annotation = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50)), style: style)
        let document = Document(source: solidSource(BrandPalette.ink), scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        TestImages.assertClose(TestImages.pixel(out, x: 85, y: 50), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 78, y: 54), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 82, y: 47), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 50, y: 58), ink)
    }

    // Ellipse (10,10,80,80) fill lime is a circle of radius 40 centered at (50,50). Its corner (12,12) is
    // distance ~53.7 from the center -- well outside both the circle and its inset stroke ring.
    func testEllipseLeavesCornersUntouched() throws {
        let style = AnnotationStyle(fillColor: BrandPalette.lime)
        let annotation = Annotation(shape: .ellipse(CGRect(x: 10, y: 10, width: 80, height: 80)), style: style)
        let document = Document(source: solidSource(BrandPalette.ink), scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        TestImages.assertClose(TestImages.pixel(out, x: 50, y: 50), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 12, y: 12), ink)
    }

    // Bone source, lime highlight over (20,20,40,40), multiply blend at alpha 0.35: Cr = Cb*(1 - a*(1-Cs)).
    // Blue: 0.9098*(1 - 0.35*(1 - 0.2471)) = 0.670 -> 171, well below bone's 232. Green stays ~unchanged (lime's
    // green is 1.0, so the multiply barely touches it), leaving green far above blue where before the gap was
    // tiny -- a visible green tint. Outside the rect the source is untouched.
    func testHighlightMultiplies() throws {
        let style = AnnotationStyle(strokeColor: BrandPalette.lime)
        let annotation = Annotation(shape: .highlight(CGRect(x: 20, y: 20, width: 40, height: 40)), style: style)
        let document = Document(source: solidSource(BrandPalette.bone), scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        let inside = TestImages.pixel(out, x: 40, y: 40)
        XCTAssertLessThan(inside.b, bone.b - 20)
        XCTAssertGreaterThan(inside.g, inside.b + 40)
        TestImages.assertClose(TestImages.pixel(out, x: 5, y: 5), bone)
    }

    // An 8px ink/lime checkerboard loses nearly all its contrast under a gaussian blur (radius
    // max(6, 0.012*100) = 6): a region well inside the blurred rect drops in red-channel variance by far more
    // than 4x. A pixel outside the rect is untouched.
    func testBlurLowersVariance() throws {
        let source = checkerboard(width: 100, height: 100, square: 8, a: BrandPalette.ink, b: BrandPalette.lime)
        let annotation = Annotation(shape: .blur(CGRect(x: 20, y: 20, width: 50, height: 50), mode: .gaussian), style: AnnotationStyle())
        let document = Document(source: source, scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        let region = CGRect(x: 30, y: 30, width: 20, height: 20)
        let before = variance(source, region: region, channel: 0)
        let after = variance(out, region: region, channel: 0)
        XCTAssertLessThan(after, before / 4)
        TestImages.assertClose(TestImages.pixel(out, x: 5, y: 5), TestImages.pixel(source, x: 5, y: 5))
    }

    // A 4px ink/lime checkerboard pixelated at scale max(8, 0.02*100) = 8 collapses to flat blocks: two points
    // well inside the blurred rect and clear of its edges land in the same flat-colored block.
    func testPixelateMakesFlatBlocks() throws {
        let source = checkerboard(width: 100, height: 100, square: 4, a: BrandPalette.ink, b: BrandPalette.lime)
        let annotation = Annotation(shape: .blur(CGRect(x: 20, y: 20, width: 50, height: 50), mode: .pixelate), style: AnnotationStyle())
        let document = Document(source: source, scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        let a = TestImages.pixel(out, x: 35, y: 35)
        let b = TestImages.pixel(out, x: 40, y: 40)
        TestImages.assertClose(a, b, tolerance: 2)
    }

    // "IL" in lime, .text family, fontSize 40, origin (20,10): AnnotationBounds gives (20, 10, 34.79, 51.0), so
    // the top third is y in [10, 27) and the bottom third y in [44, 61). (25,22) lands on the "I" stroke, in the
    // top third; (36,45) lands on the foot of the "L", in the bottom third -- proving a glyph paints across the
    // whole height rather than only above or only below the origin. Nothing above the bounds' top edge is lime.
    func testTextDrawsUpright() throws {
        try XCTSkipIf(CoreTypeface.font(.text, size: 40, weight: 600) == nil, "Onest font not available in this environment")
        let style = AnnotationStyle(strokeColor: BrandPalette.lime, fontFamily: .text, fontSize: 40)
        let annotation = Annotation(shape: .text(origin: CGPoint(x: 20, y: 10), string: "IL"), style: style)
        let document = Document(source: solidSource(BrandPalette.ink, width: 200, height: 100), scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        let bounds = AnnotationBounds.bounds(of: annotation)

        TestImages.assertClose(TestImages.pixel(out, x: 25, y: 22), lime)
        XCTAssertLessThan(22, bounds.minY + bounds.height / 3)
        TestImages.assertClose(TestImages.pixel(out, x: 36, y: 45), lime)
        XCTAssertGreaterThanOrEqual(45, bounds.minY + 2 * bounds.height / 3)

        for y in 0..<Int(bounds.minY) {
            for x in stride(from: Int(bounds.minX), through: Int(bounds.minX + bounds.width), by: 4) {
                TestImages.assertClose(TestImages.pixel(out, x: x, y: y), ink)
            }
        }
    }

    // Step badge at (50,50), number 3, fontSize 20: circle radius fontSize*0.9 = 18. The center pixel is
    // covered by the digit's ink stroke, not the lime badge fill. (62,50) is 12px right of center, on the badge
    // and clear of the digit. (50,75) is 25px below center -- outside the circle (edge at y=68) -- so the
    // source's ink shows through.
    func testStepBadge() throws {
        let style = AnnotationStyle(strokeColor: BrandPalette.lime, fontFamily: .mono, fontSize: 20)
        let annotation = Annotation(shape: .step(center: CGPoint(x: 50, y: 50), number: 3), style: style)
        let document = Document(source: solidSource(BrandPalette.ink), scaleFactor: 1, annotations: [annotation])
        let out = try XCTUnwrap(AnnotationRenderer.renderWithoutBackground(document))
        let center = TestImages.pixel(out, x: 50, y: 50)
        XCTAssertLessThan(center.g, 100, "the digit's ink should cover the exact center, not the lime badge fill")
        TestImages.assertClose(TestImages.pixel(out, x: 62, y: 50), lime)
        TestImages.assertClose(TestImages.pixel(out, x: 50, y: 75), ink)
    }

    // paddingPercent 0 keeps the canvas edge-to-edge (same size as the source). paddingPercent 20 on a 100x100
    // source has reference (100+100)/2=100, so raw padding is 20px -- below the 24px floor, so the floor wins:
    // canvas grows by 24px on every side, 100 + 24*2 = 148.
    func testRenderAppliesBackground() throws {
        let source = solidSource(BrandPalette.coral)
        let flush = BackgroundPreset(id: "flush", name: "Flush", fill: .solid(color: BrandPalette.bone), paddingPercent: 0, cornerRadiusPercent: 0, shadow: nil)
        let flushOut = try XCTUnwrap(AnnotationRenderer.render(Document(source: source, scaleFactor: 1, background: flush)))
        XCTAssertEqual(flushOut.width, 100)
        XCTAssertEqual(flushOut.height, 100)

        let padded = BackgroundPreset(id: "padded", name: "Padded", fill: .solid(color: BrandPalette.bone), paddingPercent: 20, cornerRadiusPercent: 0, shadow: nil)
        let paddedOut = try XCTUnwrap(AnnotationRenderer.render(Document(source: source, scaleFactor: 1, background: padded)))
        XCTAssertEqual(paddedOut.width, 148)
        XCTAssertEqual(paddedOut.height, 148)
    }
}
