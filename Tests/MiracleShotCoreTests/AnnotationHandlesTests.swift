import XCTest
@testable import MiracleShotCore

final class AnnotationHandlesTests: XCTestCase {
    // MARK: handles(for:)

    func testHandlesForRect() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 50)), style: AnnotationStyle())
        let handles = AnnotationHandles.handles(for: annotation)
        let byHandle = Dictionary(uniqueKeysWithValues: handles)
        XCTAssertEqual(handles.count, 8)
        XCTAssertEqual(byHandle[.topLeft], CGPoint(x: 0, y: 0))
        XCTAssertEqual(byHandle[.top], CGPoint(x: 50, y: 0))
        XCTAssertEqual(byHandle[.topRight], CGPoint(x: 100, y: 0))
        XCTAssertEqual(byHandle[.right], CGPoint(x: 100, y: 25))
        XCTAssertEqual(byHandle[.bottomRight], CGPoint(x: 100, y: 50))
        XCTAssertEqual(byHandle[.bottom], CGPoint(x: 50, y: 50))
        XCTAssertEqual(byHandle[.bottomLeft], CGPoint(x: 0, y: 50))
        XCTAssertEqual(byHandle[.left], CGPoint(x: 0, y: 25))
    }

    func testHandlesForArrow() {
        let annotation = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 40)), style: AnnotationStyle())
        let handles = AnnotationHandles.handles(for: annotation)
        let byHandle = Dictionary(uniqueKeysWithValues: handles)
        XCTAssertEqual(handles.count, 2)
        XCTAssertEqual(byHandle[.start], CGPoint(x: 10, y: 10))
        XCTAssertEqual(byHandle[.end], CGPoint(x: 90, y: 40))
    }

    func testFreehandTextAndStepOfferNoHandles() {
        XCTAssertTrue(AnnotationHandles.handles(for: Annotation(shape: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]),
                                                                  style: AnnotationStyle())).isEmpty)
        XCTAssertTrue(AnnotationHandles.handles(for: Annotation(shape: .text(origin: .zero, string: "hi"),
                                                                  style: AnnotationStyle())).isEmpty)
        XCTAssertTrue(AnnotationHandles.handles(for: Annotation(shape: .step(center: .zero, number: 1),
                                                                  style: AnnotationStyle())).isEmpty)
    }

    // MARK: handle(at:)

    func testHandleAtPicksNearestWithinTolerance() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        // (98, 97) is distance hypot(2, 3) = 3.6 from bottomRight (100, 100); within tolerance 5.
        XCTAssertEqual(AnnotationHandles.handle(at: CGPoint(x: 98, y: 97), in: annotation, tolerance: 5), .bottomRight)
    }

    func testHandleAtReturnsNilOutsideTolerance() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        // Center point (50, 50) is 50 away from every handle; far outside tolerance 5.
        XCTAssertNil(AnnotationHandles.handle(at: CGPoint(x: 50, y: 50), in: annotation, tolerance: 5))
    }

    // MARK: resized

    func testResizedKeepsOppositeCornerFixed() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .bottomRight, to: CGPoint(x: 150, y: 120))
        guard case .rect(let rect) = resized.shape else { return XCTFail("expected rect") }
        // topLeft (0, 0) stays fixed; bottomRight moves to the dragged point.
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 150, height: 120))
    }

    func testResizedFlipsCleanlyDraggingTopLeftPastBottomRight() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .topLeft, to: CGPoint(x: 150, y: 150))
        guard case .rect(let rect) = resized.shape else { return XCTFail("expected rect") }
        // bottomRight (100, 100) stays fixed; standardizing (150,150)-(100,100) gives origin (100,100), size (50,50).
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 50, height: 50))
    }

    func testResizedEdgeHandleMovesOnlyThatEdge() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .right, to: CGPoint(x: 130, y: -999))
        guard case .rect(let rect) = resized.shape else { return XCTFail("expected rect") }
        // .right only moves maxX; the y coordinate of the dragged point is ignored.
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 130, height: 100))
    }

    func testResizedEllipseUsesSameRectLogic() {
        let annotation = Annotation(shape: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 100)), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .bottom, to: CGPoint(x: 999, y: 40))
        guard case .ellipse(let rect) = resized.shape else { return XCTFail("expected ellipse") }
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 100, height: 40))
    }

    func testResizedLineMovesOnlyDraggedEndpoint() {
        let annotation = Annotation(shape: .line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100)), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .start, to: CGPoint(x: 20, y: 30))
        guard case .line(let from, let to) = resized.shape else { return XCTFail("expected line") }
        XCTAssertEqual(from, CGPoint(x: 20, y: 30))
        XCTAssertEqual(to, CGPoint(x: 100, y: 100))
    }

    func testResizedArrowMovesOnlyDraggedEndpoint() {
        let annotation = Annotation(shape: .arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100)), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .end, to: CGPoint(x: 40, y: 60))
        guard case .arrow(let from, let to) = resized.shape else { return XCTFail("expected arrow") }
        XCTAssertEqual(from, CGPoint(x: 0, y: 0))
        XCTAssertEqual(to, CGPoint(x: 40, y: 60))
    }

    func testResizedIsNoOpForShapesWithoutHandles() {
        let annotation = Annotation(shape: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]), style: AnnotationStyle())
        let resized = AnnotationHandles.resized(annotation, handle: .topLeft, to: CGPoint(x: 999, y: 999))
        XCTAssertEqual(resized, annotation)
    }

    func testResizedIsNoOpForLineWithRectOnlyHandle() {
        let annotation = Annotation(shape: .line(from: .zero, to: CGPoint(x: 100, y: 100)), style: AnnotationStyle())
        XCTAssertEqual(AnnotationHandles.resized(annotation, handle: .top, to: CGPoint(x: 999, y: 999)), annotation)
    }

    /// Equidistant handles resolve in `handles(for:)` order: (2.5, 0) is 2.5 from both `topLeft` and `top`.
    func testHandleAtTieGoesToTheFirstHandleInOrder() {
        let annotation = Annotation(shape: .rect(CGRect(x: 0, y: 0, width: 10, height: 10)), style: AnnotationStyle())
        XCTAssertEqual(AnnotationHandles.handle(at: CGPoint(x: 2.5, y: 0), in: annotation, tolerance: 10), .topLeft)
    }
}
