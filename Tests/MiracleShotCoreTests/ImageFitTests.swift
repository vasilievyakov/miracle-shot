import XCTest
@testable import MiracleShotCore

final class ImageFitTests: XCTestCase {
    func testScalesDownProportionallyToFitBox() {
        let size = ImageFit.size(CGSize(width: 2400, height: 1600), into: CGSize(width: 240, height: 150))
        XCTAssertEqual(size, CGSize(width: 225, height: 150))
    }

    func testNeverScalesUp() {
        let size = ImageFit.size(CGSize(width: 100, height: 50), into: CGSize(width: 240, height: 150))
        XCTAssertEqual(size, CGSize(width: 100, height: 50))
    }

    func testTinyImageGrowsUniformlyToMinimum() {
        XCTAssertEqual(ImageFit.size(CGSize(width: 10, height: 10), into: CGSize(width: 240, height: 150)),
                       CGSize(width: 40, height: 40))
    }

    func testThinStripKeepsAspectRatio() {
        let s = ImageFit.size(CGSize(width: 1000, height: 10), into: CGSize(width: 240, height: 150))
        XCTAssertEqual(s.width, 240)
        XCTAssertEqual(s.height, 2)
    }

    func testZeroSizeYieldsMinimum() {
        let size = ImageFit.size(.zero, into: CGSize(width: 240, height: 150))
        XCTAssertEqual(size, CGSize(width: 60, height: 40))
    }
}
