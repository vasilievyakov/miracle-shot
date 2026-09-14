import XCTest
@testable import MiracleShotCore

final class ArrowGeometryTests: XCTestCase {
    func testTipEqualsTo() {
        let head = ArrowGeometry.head(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 4)
        XCTAssertEqual(head.tip, CGPoint(x: 100, y: 0))
    }

    func testLeftAndRightAreSymmetricAboutTheShaft() {
        // Horizontal shaft (y = 0): left and right must mirror across the shaft line.
        let head = ArrowGeometry.head(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 4)
        XCTAssertEqual(head.left.x, head.right.x, accuracy: 0.0001)
        XCTAssertEqual(head.left.y, -head.right.y, accuracy: 0.0001)
        XCTAssertTrue(abs(head.left.y) > 0.0001)
    }

    func testHeadLengthIsMaxOf12AndFourTimesLineWidth() {
        // lineWidth 1 -> 4 * 1 = 4, floored to 12.
        let thin = ArrowGeometry.head(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 1)
        XCTAssertEqual(hypot(thin.tip.x - thin.left.x, thin.tip.y - thin.left.y), 12, accuracy: 0.0001)
        // lineWidth 5 -> 4 * 5 = 20, above the floor.
        let thick = ArrowGeometry.head(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 5)
        XCTAssertEqual(hypot(thick.tip.x - thick.left.x, thick.tip.y - thick.left.y), 20, accuracy: 0.0001)
    }

    func testShaftEndLiesOnTheShaftAxis() {
        // Vertical shaft (x = 10, from y=10 to y=110): shaftEnd must sit back from the tip along the same
        // axis, at distance headLength * cos(28 degrees) = 16 * cos(28deg) ~= 14.13.
        let head = ArrowGeometry.head(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10, y: 110), lineWidth: 4)
        XCTAssertEqual(head.shaftEnd.x, 10, accuracy: 0.0001)
        XCTAssertEqual(head.shaftEnd.y, 110 - 16 * cos(28 * .pi / 180), accuracy: 0.0001)
    }

    func testZeroLengthArrowCollapsesEveryPointToTo() {
        let to = CGPoint(x: 5, y: 5)
        let head = ArrowGeometry.head(from: to, to: to, lineWidth: 4)
        XCTAssertEqual(head.tip, to)
        XCTAssertEqual(head.left, to)
        XCTAssertEqual(head.right, to)
        XCTAssertEqual(head.shaftEnd, to)
    }
}
