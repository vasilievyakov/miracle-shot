import XCTest
@testable import MiracleShotCore

final class SelectionGeometryTests: XCTestCase {
    private func win(_ id: UInt32, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     layer: Int = 0, pid: Int32 = 100) -> WindowInfo {
        WindowInfo(id: id, frame: CGRect(x: x, y: y, width: w, height: h), layer: layer,
                   ownerName: "App\(id)", ownerPID: pid, title: nil)
    }

    // MARK: rect(from:to:)

    func testRectNormalizesAnyDragDirection() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(SelectionGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60)), expected)
        XCTAssertEqual(SelectionGeometry.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20)), expected)
        XCTAssertEqual(SelectionGeometry.rect(from: CGPoint(x: 40, y: 20), to: CGPoint(x: 10, y: 60)), expected)
    }

    func testIsClickWithinTolerance() {
        XCTAssertTrue(SelectionGeometry.isClick(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 2, y: 2)))
        XCTAssertFalse(SelectionGeometry.isClick(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 4, y: 0)))
    }

    // MARK: window(at:)

    func testFrontmostWindowWins() {
        let front = win(1, 0, 0, 100, 100)
        let back = win(2, 0, 0, 200, 200)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 50, y: 50), in: [front, back]), front)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 150, y: 150), in: [front, back]), back)
    }

    func testNonZeroLayerWindowsAreIgnored() {
        let menuBar = win(1, 0, 0, 1000, 24, layer: 25)
        let normal = win(2, 0, 0, 1000, 500)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 10, y: 10), in: [menuBar, normal]), normal)
    }

    func testOwnPIDIsExcluded() {
        let overlay = win(1, 0, 0, 1000, 1000, pid: 42)
        let normal = win(2, 0, 0, 500, 500, pid: 7)
        XCTAssertEqual(SelectionGeometry.window(at: CGPoint(x: 10, y: 10), in: [overlay, normal], excludingPID: 42), normal)
    }

    func testNoWindowUnderPoint() {
        XCTAssertNil(SelectionGeometry.window(at: CGPoint(x: 999, y: 999), in: [win(1, 0, 0, 10, 10)]))
    }

    // MARK: snapped

    func testEdgesSnapWithinThreshold() {
        let w = win(1, 100, 100, 300, 200)   // edges x: 100/400, y: 100/300
        let rect = CGRect(x: 105, y: 96, width: 290, height: 210)   // edges 105/395, 96/306
        let snapped = SelectionGeometry.snapped(rect, to: [w], threshold: 8)
        XCTAssertEqual(snapped, CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    func testEdgesBeyondThresholdDoNotSnap() {
        let w = win(1, 100, 100, 300, 200)
        let rect = CGRect(x: 120, y: 120, width: 100, height: 100)
        XCTAssertEqual(SelectionGeometry.snapped(rect, to: [w], threshold: 8), rect)
    }

    func testSnapPicksNearestEdge() {
        let a = win(1, 0, 0, 100, 100)     // maxX = 100
        let b = win(2, 103, 0, 100, 100)   // minX = 103
        let rect = CGRect(x: 102, y: 50, width: 20, height: 10)
        XCTAssertEqual(SelectionGeometry.snapped(rect, to: [a, b], threshold: 8).minX, 103)
    }

    // MARK: magnifier

    func testMagnifierSitsBottomRightOfCursor() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 100, y: 100), size: 120, offset: 20, in: screen)
        XCTAssertEqual(f, CGRect(x: 120, y: 120, width: 120, height: 120))
    }

    func testMagnifierFlipsNearRightAndBottomEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 950, y: 750), size: 120, offset: 20, in: screen)
        XCTAssertEqual(f, CGRect(x: 950 - 20 - 120, y: 750 - 20 - 120, width: 120, height: 120))
    }

    // MARK: pixel alignment and flipping

    func testPixelAlignedRoundsToDevicePixels() {
        // Corners: 10.3 -> 10.5, 10.7 -> 10.5, maxX 30.5 -> 30.5, maxY 31.3 -> 31.5 at scale 2.
        let r = SelectionGeometry.pixelAligned(CGRect(x: 10.3, y: 10.7, width: 20.2, height: 20.6), scale: 2)
        XCTAssertEqual(r, CGRect(x: 10.5, y: 10.5, width: 20, height: 21))
    }

    func testPixelAlignedKeepsFarEdgesOnRoundedPixels() {
        let rect = CGRect(x: 0.4, y: 0.4, width: 10.3, height: 10.3)   // maxX = 10.7 -> 11 at scale 1
        let r = SelectionGeometry.pixelAligned(rect, scale: 1)
        XCTAssertEqual(r.minX, 0)
        XCTAssertEqual(r.maxX, 11)
        XCTAssertEqual(r.maxY, 11)
    }

    func testSnapCanCollapseToZeroHeight() {
        let w = win(1, 100, 100, 300, 200)   // minY = 100
        let rect = CGRect(x: 120, y: 97, width: 50, height: 6)   // edges 97 and 103, both within 8 of 100
        let snapped = SelectionGeometry.snapped(rect, to: [w], threshold: 8)
        XCTAssertEqual(snapped.height, 0)
        XCTAssertEqual(snapped.minY, 100)
    }

    func testMagnifierFlipsOnSecondaryDisplayWithNonZeroOrigin() {
        let screen = CGRect(x: 2000, y: -200, width: 1000, height: 800)
        let near = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 2100, y: -100), size: 120, offset: 20, in: screen)
        XCTAssertEqual(near, CGRect(x: 2120, y: -80, width: 120, height: 120))
        let far = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 2950, y: 550), size: 120, offset: 20, in: screen)
        XCTAssertEqual(far, CGRect(x: 2950 - 140, y: 550 - 140, width: 120, height: 120))
    }

    func testMagnifierIsClampedIntoTinyScreen() {
        let screen = CGRect(x: 0, y: 0, width: 200, height: 200)
        let f = SelectionGeometry.magnifierFrame(cursor: CGPoint(x: 190, y: 190), size: 120, offset: 20, in: screen)
        XCTAssertTrue(screen.contains(f), "\(f) is not inside \(screen)")
    }

    func testFlippedIsAnInvolution() {
        let r = CGRect(x: 10, y: 20, width: 100, height: 50)
        let once = SelectionGeometry.flipped(r, primaryScreenHeight: 800)
        XCTAssertEqual(once, CGRect(x: 10, y: 730, width: 100, height: 50))
        XCTAssertEqual(SelectionGeometry.flipped(once, primaryScreenHeight: 800), r)
        XCTAssertEqual(SelectionGeometry.flipped(CGPoint(x: 5, y: 100), primaryScreenHeight: 800), CGPoint(x: 5, y: 700))
    }
}
