import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class ScrollRegionTests: XCTestCase {
    private let window = CGRect(x: 100, y: 50, width: 800, height: 600)

    func testAreaIsClippedToTheWindow() throws {
        let region = try XCTUnwrap(ScrollRegion(area: CGRect(x: 300, y: 0, width: 700, height: 500), window: window))
        XCTAssertEqual(region.frame, CGRect(x: 300, y: 50, width: 600, height: 450))
    }

    func testTinyOrOutsideAreasAreRejected() {
        XCTAssertNil(ScrollRegion(area: CGRect(x: 300, y: 100, width: 40, height: 400), window: window))
        XCTAssertNil(ScrollRegion(area: CGRect(x: 2000, y: 100, width: 400, height: 400), window: window))
        XCTAssertNil(ScrollRegion(area: .zero, window: window))
    }

    func testPixelRectIsRelativeToTheWindowScaledAndIntegral() throws {
        let region = try XCTUnwrap(ScrollRegion(area: CGRect(x: 300.4, y: 100.6, width: 400.2, height: 300.3), window: window))
        let rect = region.pixelRect(scale: 2)
        XCTAssertEqual(rect, CGRect(x: 400, y: 101, width: 802, height: 601))
    }

    func testCropTakesTheRegionOutOfAWindowImage() throws {
        let region = try XCTUnwrap(ScrollRegion(area: CGRect(x: 500, y: 350, width: 400, height: 300), window: window))
        let image = TestImages.splitHorizontally(width: 1600, height: 1200,
                                                  top: TestImages.RGBA(r: 200, g: 0, b: 0, a: 255),
                                                  bottom: TestImages.RGBA(r: 0, g: 0, b: 200, a: 255))
        let cropped = try XCTUnwrap(region.crop(image, scale: 2))
        XCTAssertEqual(cropped.width, 800)
        XCTAssertEqual(cropped.height, 600)
        // The region is the bottom-right quarter of the window: all blue.
        TestImages.assertClose(TestImages.pixel(cropped, x: 10, y: 10), TestImages.RGBA(r: 0, g: 0, b: 200, a: 255))
    }

    func testCropReturnsNilWhenTheImageDoesNotCoverTheRegion() throws {
        let region = try XCTUnwrap(ScrollRegion(area: CGRect(x: 500, y: 350, width: 400, height: 300), window: window))
        let small = TestImages.solid(width: 100, height: 100, r: 1, g: 1, b: 1)
        XCTAssertNil(region.crop(small, scale: 2))
    }
}
