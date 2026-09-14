import XCTest
@testable import MiracleShotCore

final class AnnotationHitTestTests: XCTestCase {
    private let noBounds: (Annotation) -> CGRect = { _ in .zero }

    // MARK: topmost wins

    func testTopmostAnnotationWinsWhenBothOverlap() {
        let back = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        let front = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 50, height: 50)), style: AnnotationStyle())
        // annotations are ordered back-to-front, like Document.annotations; both contain (25, 25).
        let hit = AnnotationHitTest.hit(CGPoint(x: 25, y: 25), in: [back, front], tolerance: 2, bounds: noBounds)
        XCTAssertEqual(hit?.id, front.id)
    }

    // MARK: rect / blur / highlight

    func testRectHitInsideAndNearBorderNotFarOutside() {
        let rect = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 50)), style: AnnotationStyle())
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 50, y: 25), in: [rect], tolerance: 2, bounds: noBounds))
        // (101, 25) is 1pt past the right edge: distance 1 <= tolerance 2.
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 101, y: 25), in: [rect], tolerance: 2, bounds: noBounds))
        // (200, 25) is 100pt past the right edge: distance 100 > tolerance 2.
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 200, y: 25), in: [rect], tolerance: 2, bounds: noBounds))
    }

    // MARK: ellipse

    func testEllipseExcludesCornerInsideRectButOutsideEllipse() {
        let ellipse = Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        // (0, 0): inside the bounding rect, but normalized ((0-50)/50)^2 * 2 = 2 > 1, even after growing the
        // rect by tolerance 2 (rx = ry = 52: ((0-51)/51)^2 * 2 ~= 1.96 > 1) -- outside the ellipse.
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 0, y: 0), in: [ellipse], tolerance: 2, bounds: noBounds))
        // Center is always inside.
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 50, y: 50), in: [ellipse], tolerance: 2, bounds: noBounds))
    }

    // MARK: line / arrow / freehand

    func testLineHitUsesSegmentDistancePlusHalfLineWidth() {
        var style = AnnotationStyle()
        style.lineWidth = 4   // halfStroke = 2, so effective tolerance = 2 + 2 = 4
        let line = Annotation(shape: .line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), style: style)
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 50, y: 3), in: [line], tolerance: 2, bounds: noBounds))
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 50, y: 5), in: [line], tolerance: 2, bounds: noBounds))
        // Beyond the segment end: distance measures to the endpoint (100, 0), 50pt away.
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 150, y: 0), in: [line], tolerance: 2, bounds: noBounds))
    }

    func testArrowUsesSameSegmentDistanceAsLine() {
        var style = AnnotationStyle()
        style.lineWidth = 4
        let arrow = Annotation(shape: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)), style: style)
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 50, y: 3), in: [arrow], tolerance: 2, bounds: noBounds))
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 50, y: 5), in: [arrow], tolerance: 2, bounds: noBounds))
    }

    func testFreehandHitsAnySegment() {
        var style = AnnotationStyle()
        style.lineWidth = 4
        let freehand = Annotation(shape: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)]), style: style)
        // near the second segment (x = 50, y in 0...50): (52, 25) is 2pt away <= tolerance 2 + halfStroke 2 = 4.
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 52, y: 25), in: [freehand], tolerance: 2, bounds: noBounds))
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 100, y: 100), in: [freehand], tolerance: 2, bounds: noBounds))
    }

    // MARK: text

    func testTextHitUsesCallerProvidedBounds() {
        let text = Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: "hi"), style: AnnotationStyle())
        let bounds: (Annotation) -> CGRect = { _ in CGRect(x: 10, y: 10, width: 40, height: 20) }
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 20, y: 15), in: [text], tolerance: 2, bounds: bounds))
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 100, y: 100), in: [text], tolerance: 2, bounds: bounds))
    }

    // MARK: step

    func testStepHitIsWithinFontSizeRadiusOfCenter() {
        var style = AnnotationStyle()
        style.fontSize = 20
        let step = Annotation(shape: .step(center: CGPoint(x: 50, y: 50), number: 1), style: style)
        XCTAssertNotNil(AnnotationHitTest.hit(CGPoint(x: 50 + 19, y: 50), in: [step], tolerance: 0, bounds: noBounds))
        XCTAssertNil(AnnotationHitTest.hit(CGPoint(x: 50 + 21, y: 50), in: [step], tolerance: 0, bounds: noBounds))
    }

    // MARK: distance(from:toSegment:)

    func testDistanceToSegmentBeyondEndMeasuresToEndpoint() {
        let d = AnnotationHitTest.distance(from: CGPoint(x: 150, y: 0), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        XCTAssertEqual(d, 50)
    }

    func testDistanceToSegmentPerpendicularProjection() {
        // (50, 30) projects onto x=50 on the segment; distance is the perpendicular offset, 30.
        let d = AnnotationHitTest.distance(from: CGPoint(x: 50, y: 30), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0))
        XCTAssertEqual(d, 30)
    }

    func testDistanceToDegenerateSegmentMeasuresToPoint() {
        // a == b: a 3-4-5 triangle from (0,0) to (3,4).
        let d = AnnotationHitTest.distance(from: CGPoint(x: 3, y: 4), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0))
        XCTAssertEqual(d, 5)
    }
}
