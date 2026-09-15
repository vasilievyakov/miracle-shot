import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class FrameDiffTests: XCTestCase {
    /// A solid `base` image with its top `bandRows` rows recolored to `band`; used to model a changed strip
    /// near the top of a scrolled frame, e.g. a sticky header that did move.
    private func topBand(width: Int, height: Int, bandRows: Int, base: BrandColor, band: BrandColor) -> CGImage {
        let ctx = TestImages.context(width: width, height: height)
        ctx.setFillColor(base.cgColor())
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(band.cgColor())
        // CG drawing is bottom-left origin; the topmost `bandRows` pixel rows are the top of the drawing rect.
        ctx.fill(CGRect(x: 0, y: height - bandRows, width: width, height: bandRows))
        return ctx.makeImage()!
    }

    func testIdenticalFramesHaveZeroDifference() {
        let a = TestImages.solid(width: 64, height: 64, r: 0.4, g: 0.5, b: 0.6)
        let b = TestImages.solid(width: 64, height: 64, r: 0.4, g: 0.5, b: 0.6)
        XCTAssertEqual(FrameDiff.difference(a, b), 0)
    }

    func testInverseFramesAreCloseToOne() {
        let black = TestImages.solid(width: 32, height: 32, r: 0, g: 0, b: 0)
        let white = TestImages.solid(width: 32, height: 32, r: 1, g: 1, b: 1)
        XCTAssertEqual(FrameDiff.difference(black, white), 1, accuracy: 0.01)
    }

    func testTenPercentChangedBandFallsBetween5And15Percent() {
        let a = topBand(width: 64, height: 100, bandRows: 10, base: BrandPalette.ink, band: BrandPalette.ink)
        let b = topBand(width: 64, height: 100, bandRows: 10, base: BrandPalette.ink, band: BrandPalette.bone)
        let diff = FrameDiff.difference(a, b)
        XCTAssertGreaterThan(diff, 0.05)
        XCTAssertLessThan(diff, 0.15)
    }

    func testDifferentSizesReturnOne() {
        let a = TestImages.solid(width: 10, height: 10, r: 0, g: 0, b: 0)
        let b = TestImages.solid(width: 20, height: 20, r: 0, g: 0, b: 0)
        XCTAssertEqual(FrameDiff.difference(a, b), 1)
    }

    func testRowDifferencesMarksChangedRowAndLeavesOthersAtZero() {
        let a = topBand(width: 128, height: 10, bandRows: 1, base: BrandPalette.ink, band: BrandPalette.ink)
        let b = topBand(width: 128, height: 10, bandRows: 1, base: BrandPalette.ink, band: BrandPalette.bone)
        // rowCount == height samples every row exactly once (y = r * 9 / 9 = r).
        let rows = FrameDiff.rowDifferences(a, b, rowCount: 10)
        XCTAssertEqual(rows.count, 10)
        XCTAssertGreaterThan(rows[0], 0.5)
        for row in rows.dropFirst() {
            XCTAssertEqual(row, 0)
        }
    }

    func testRowDifferencesDifferentSizesReturnsArrayOfOnes() {
        let a = TestImages.solid(width: 10, height: 10, r: 0, g: 0, b: 0)
        let b = TestImages.solid(width: 20, height: 20, r: 0, g: 0, b: 0)
        XCTAssertEqual(FrameDiff.rowDifferences(a, b, rowCount: 5), [1, 1, 1, 1, 1])
    }

    func testDegenerateGridsAndTinyImagesDoNotCrash() {
        let a = TestImages.solid(width: 1, height: 1, r: 0, g: 0, b: 0)
        let b = TestImages.solid(width: 1, height: 1, r: 1, g: 1, b: 1)
        XCTAssertEqual(FrameDiff.difference(a, b, grid: 1), 1, accuracy: 0.01)
        XCTAssertEqual(FrameDiff.difference(a, a, grid: 1), 0)
        XCTAssertEqual(FrameDiff.rowDifferences(a, b, rowCount: 5).count, 5)
    }
}
