import XCTest
@testable import MiracleShotCore

final class AnnotationTests: XCTestCase {
    private func style() -> AnnotationStyle {
        AnnotationStyle(strokeColor: BrandPalette.lime, fillColor: nil, lineWidth: 4, fontFamily: .text, fontSize: 28)
    }

    // MARK: geometryBounds

    func testArrowBoundsSpanBothPoints() {
        let arrow = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 50, y: 80)), style: style())
        XCTAssertEqual(arrow.geometryBounds, CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    func testReversedArrowBoundsStandardize() {
        let arrow = Annotation(shape: .arrow(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20)), style: style())
        XCTAssertEqual(arrow.geometryBounds, CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    func testLineBoundsSpanBothPoints() {
        let line = Annotation(shape: .line(from: CGPoint(x: 30, y: 10), to: CGPoint(x: 5, y: 45)), style: style())
        XCTAssertEqual(line.geometryBounds, CGRect(x: 5, y: 10, width: 25, height: 35))
    }

    func testRectBoundsAreStandardized() {
        let rect = Annotation(shape: .rect(CGRect(x: 40, y: 40, width: -20, height: -10)), style: style())
        XCTAssertEqual(rect.geometryBounds, CGRect(x: 20, y: 30, width: 20, height: 10))
    }

    func testEllipseBoundsAreStandardized() {
        let ellipse = Annotation(shape: .ellipse(CGRect(x: 10, y: 10, width: 30, height: 20)), style: style())
        XCTAssertEqual(ellipse.geometryBounds, CGRect(x: 10, y: 10, width: 30, height: 20))
    }

    func testBlurBoundsAreStandardized() {
        let blur = Annotation(shape: .blur(CGRect(x: 30, y: 30, width: -10, height: -10), mode: .pixelate), style: style())
        XCTAssertEqual(blur.geometryBounds, CGRect(x: 20, y: 20, width: 10, height: 10))
    }

    func testHighlightBoundsAreStandardized() {
        let highlight = Annotation(shape: .highlight(CGRect(x: 5, y: 5, width: 15, height: 25)), style: style())
        XCTAssertEqual(highlight.geometryBounds, CGRect(x: 5, y: 5, width: 15, height: 25))
    }

    func testFreehandBoundsSpanAllPoints() {
        let points = [CGPoint(x: 5, y: 40), CGPoint(x: 30, y: 5), CGPoint(x: 20, y: 60)]
        let freehand = Annotation(shape: .freehand(points), style: style())
        XCTAssertEqual(freehand.geometryBounds, CGRect(x: 5, y: 5, width: 25, height: 55))
    }

    func testEmptyFreehandBoundsAreZero() {
        let freehand = Annotation(shape: .freehand([]), style: style())
        XCTAssertEqual(freehand.geometryBounds, .zero)
    }

    func testTextBoundsAreZeroSizedAtOrigin() {
        let text = Annotation(shape: .text(origin: CGPoint(x: 12, y: 34), string: "hi"), style: style())
        XCTAssertEqual(text.geometryBounds, CGRect(origin: CGPoint(x: 12, y: 34), size: .zero))
    }

    func testStepBoundsAreASquareCenteredOnPoint() {
        let step = Annotation(shape: .step(center: CGPoint(x: 100, y: 100), number: 1), style: style())
        let side = style().fontSize * 2
        let expected = CGRect(x: 100 - side / 2, y: 100 - side / 2, width: side, height: side)
        XCTAssertEqual(step.geometryBounds, expected)
    }

    // MARK: moved(by:)

    func testMovedShiftsArrowPoints() {
        let arrow = Annotation(shape: .arrow(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 50, y: 80)), style: style())
        let moved = arrow.moved(by: CGPoint(x: 5, y: -5))
        XCTAssertEqual(moved.shape, .arrow(from: CGPoint(x: 15, y: 15), to: CGPoint(x: 55, y: 75)))
        XCTAssertEqual(moved.id, arrow.id)
        XCTAssertEqual(moved.style, arrow.style)
    }

    func testMovedShiftsLinePoints() {
        let line = Annotation(shape: .line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10)), style: style())
        let moved = line.moved(by: CGPoint(x: 3, y: 4))
        XCTAssertEqual(moved.shape, .line(from: CGPoint(x: 3, y: 4), to: CGPoint(x: 13, y: 14)))
    }

    func testMovedShiftsRect() {
        let rect = Annotation(shape: .rect(CGRect(x: 10, y: 10, width: 20, height: 20)), style: style())
        let moved = rect.moved(by: CGPoint(x: -5, y: 5))
        XCTAssertEqual(moved.shape, .rect(CGRect(x: 5, y: 15, width: 20, height: 20)))
    }

    func testMovedShiftsEllipse() {
        let ellipse = Annotation(shape: .ellipse(CGRect(x: 10, y: 10, width: 20, height: 20)), style: style())
        let moved = ellipse.moved(by: CGPoint(x: 1, y: 2))
        XCTAssertEqual(moved.shape, .ellipse(CGRect(x: 11, y: 12, width: 20, height: 20)))
    }

    func testMovedShiftsBlur() {
        let blur = Annotation(shape: .blur(CGRect(x: 10, y: 10, width: 20, height: 20), mode: .gaussian), style: style())
        let moved = blur.moved(by: CGPoint(x: 2, y: 2))
        XCTAssertEqual(moved.shape, .blur(CGRect(x: 12, y: 12, width: 20, height: 20), mode: .gaussian))
    }

    func testMovedShiftsHighlight() {
        let highlight = Annotation(shape: .highlight(CGRect(x: 10, y: 10, width: 20, height: 20)), style: style())
        let moved = highlight.moved(by: CGPoint(x: -2, y: -2))
        XCTAssertEqual(moved.shape, .highlight(CGRect(x: 8, y: 8, width: 20, height: 20)))
    }

    func testMovedShiftsAllFreehandPoints() {
        let freehand = Annotation(shape: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]), style: style())
        let moved = freehand.moved(by: CGPoint(x: 5, y: 5))
        XCTAssertEqual(moved.shape, .freehand([CGPoint(x: 5, y: 5), CGPoint(x: 15, y: 15)]))
    }

    func testMovedShiftsTextOrigin() {
        let text = Annotation(shape: .text(origin: CGPoint(x: 10, y: 10), string: "hi"), style: style())
        let moved = text.moved(by: CGPoint(x: 1, y: 1))
        XCTAssertEqual(moved.shape, .text(origin: CGPoint(x: 11, y: 11), string: "hi"))
    }

    func testMovedShiftsStepCenter() {
        let step = Annotation(shape: .step(center: CGPoint(x: 10, y: 10), number: 3), style: style())
        let moved = step.moved(by: CGPoint(x: 4, y: -4))
        XCTAssertEqual(moved.shape, .step(center: CGPoint(x: 14, y: 6), number: 3))
    }

    // MARK: AnnotationStyle.default(scaleFactor:)

    func testDefaultStyleAtScaleOneUsesBaseValues() {
        let style = AnnotationStyle.default(scaleFactor: 1)
        XCTAssertEqual(style.lineWidth, 4)
        XCTAssertEqual(style.fontSize, 28)
    }

    func testDefaultStyleDoublesLineWidthAndFontSizeAtScaleTwo() {
        let base = AnnotationStyle.default(scaleFactor: 1)
        let scaled = AnnotationStyle.default(scaleFactor: 2)
        XCTAssertEqual(scaled.lineWidth, base.lineWidth * 2)
        XCTAssertEqual(scaled.fontSize, base.fontSize * 2)
    }
}
