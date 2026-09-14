import XCTest
@testable import MiracleShotCore

final class EditorGeometryTests: XCTestCase {
    // MARK: fit

    func testFitCentersRespectsPaddingAndScalesToFit() {
        // available: 1000-2*24=952 x 800-2*24=752; scale = min(1, 952/4000, 752/2000) = min(1, 0.238, 0.376) = 0.238
        let geometry = EditorGeometry.fit(imageSize: CGSize(width: 4000, height: 2000),
                                           in: CGSize(width: 1000, height: 800), padding: 24, maxScale: 1)
        XCTAssertEqual(geometry.scale, 0.238, accuracy: 0.0001)
        // scaled image 952x476 fills the available width exactly, so origin.x == padding == 24;
        // origin.y centers the leftover vertical space: (800 - 476) / 2 = 162
        XCTAssertEqual(geometry.origin.x, 24, accuracy: 0.0001)
        XCTAssertEqual(geometry.origin.y, 162, accuracy: 0.0001)
    }

    func testFitClampsToMaxScale() {
        // Unconstrained scale would be min(952/100, 952/100) = 9.52; maxScale caps it at 2.
        let geometry = EditorGeometry.fit(imageSize: CGSize(width: 100, height: 100),
                                           in: CGSize(width: 1000, height: 1000), padding: 0, maxScale: 2)
        XCTAssertEqual(geometry.scale, 2)
        // scaled image 200x200 centered in 1000x1000
        XCTAssertEqual(geometry.origin, CGPoint(x: 400, y: 400))
    }

    func testFitFallsBackWhenAvailableSpaceIsEmpty() {
        // padding 20 on each side leaves 10 - 40 = -30 available: falls back to scale 1, origin at padding.
        let geometry = EditorGeometry.fit(imageSize: CGSize(width: 100, height: 100),
                                           in: CGSize(width: 10, height: 10), padding: 20, maxScale: 2)
        XCTAssertEqual(geometry.scale, 1)
        XCTAssertEqual(geometry.origin, CGPoint(x: 20, y: 20))
    }

    func testFitFallsBackWhenImageSizeIsZero() {
        let geometry = EditorGeometry.fit(imageSize: .zero, in: CGSize(width: 1000, height: 800), padding: 24, maxScale: 2)
        XCTAssertEqual(geometry.scale, 1)
        XCTAssertEqual(geometry.origin, CGPoint(x: 24, y: 24))
    }

    // MARK: round trip

    func testViewImagePointRoundTrip() {
        let geometry = EditorGeometry(scale: 2, origin: CGPoint(x: 10, y: 20), imageSize: CGSize(width: 500, height: 400))
        let imagePoint = CGPoint(x: 123, y: 45)
        let viewPoint = geometry.viewPoint(fromImage: imagePoint)
        XCTAssertEqual(viewPoint, CGPoint(x: 123 * 2 + 10, y: 45 * 2 + 20))
        XCTAssertEqual(geometry.imagePoint(fromView: viewPoint), imagePoint)
    }

    func testViewImageRectRoundTrip() {
        let geometry = EditorGeometry(scale: 0.5, origin: CGPoint(x: 5, y: 5), imageSize: CGSize(width: 1000, height: 1000))
        let imageRect = CGRect(x: 100, y: 200, width: 50, height: 80)
        let viewRect = geometry.viewRect(fromImage: imageRect)
        XCTAssertEqual(viewRect, CGRect(x: 100 * 0.5 + 5, y: 200 * 0.5 + 5, width: 25, height: 40))
        XCTAssertEqual(geometry.imageRect(fromView: viewRect), imageRect)
    }

    // MARK: imageLength

    func testImageLengthConvertsViewPointsToImagePixels() {
        let geometry = EditorGeometry(scale: 2, origin: .zero, imageSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(geometry.imageLength(fromView: 10), 5)
    }

    // MARK: clamped

    func testClampedKeepsPointInsideImageBounds() {
        let geometry = EditorGeometry(scale: 1, origin: .zero, imageSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(geometry.clamped(CGPoint(x: -10, y: 50)), CGPoint(x: 0, y: 50))
        XCTAssertEqual(geometry.clamped(CGPoint(x: 250, y: 500)), CGPoint(x: 200, y: 100))
        XCTAssertEqual(geometry.clamped(CGPoint(x: 100, y: 50)), CGPoint(x: 100, y: 50))
    }
}
