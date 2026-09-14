import CoreGraphics
import XCTest
@testable import MiracleShotCore

final class AnnotationBoundsTests: XCTestCase {
    private func textAnnotation(_ string: String, fontSize: CGFloat = 20, origin: CGPoint = CGPoint(x: 10, y: 10)) -> Annotation {
        Annotation(shape: .text(origin: origin, string: string), style: AnnotationStyle(fontSize: fontSize))
    }

    func testTextBoundsGrowWithTheString() {
        let short = AnnotationBounds.bounds(of: textAnnotation("I"))
        let long = AnnotationBounds.bounds(of: textAnnotation("Miracle Shot"))
        XCTAssertGreaterThan(long.width, short.width)
    }

    func testTextBoundsGrowWithFontSize() {
        let small = AnnotationBounds.bounds(of: textAnnotation("Shot", fontSize: 12))
        let large = AnnotationBounds.bounds(of: textAnnotation("Shot", fontSize: 48))
        XCTAssertGreaterThan(large.width, small.width)
        XCTAssertGreaterThan(large.height, small.height)
    }

    func testTwoLinesAreTallerThanOne() {
        let one = AnnotationBounds.bounds(of: textAnnotation("Line"))
        let two = AnnotationBounds.bounds(of: textAnnotation("Line\nTwo"))
        XCTAssertGreaterThan(two.height, one.height)
    }

    func testStepBoundsAreASquareSizedByFontSize() {
        let annotation = Annotation(shape: .step(center: CGPoint(x: 50, y: 50), number: 1), style: AnnotationStyle(fontSize: 20))
        let bounds = AnnotationBounds.bounds(of: annotation)
        XCTAssertEqual(bounds.width, bounds.height)
        XCTAssertEqual(bounds.width, 20 * 0.9 * 2)
    }
}
