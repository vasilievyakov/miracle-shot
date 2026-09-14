import XCTest
@testable import MiracleShotCore

final class DocumentTests: XCTestCase {
    private func source() -> CGImage {
        TestImages.solid(width: 100, height: 80, r: 1, g: 1, b: 1)
    }

    private func style() -> AnnotationStyle {
        AnnotationStyle(strokeColor: BrandPalette.lime, fillColor: nil, lineWidth: 4, fontFamily: .text, fontSize: 28)
    }

    private func rectAnnotation(_ side: CGFloat = 10) -> Annotation {
        Annotation(shape: .rect(CGRect(x: 0, y: 0, width: side, height: side)), style: style())
    }

    // MARK: add / update / remove / bringToFront

    func testAddAppendsAnnotation() {
        var doc = Document(source: source(), scaleFactor: 1)
        let annotation = rectAnnotation()
        doc.add(annotation)
        XCTAssertEqual(doc.annotations, [annotation])
    }

    func testUpdateReplacesAnnotationById() {
        var doc = Document(source: source(), scaleFactor: 1)
        var annotation = rectAnnotation()
        doc.add(annotation)
        annotation.shape = .rect(CGRect(x: 5, y: 5, width: 20, height: 20))
        doc.update(annotation)
        XCTAssertEqual(doc.annotation(id: annotation.id)?.shape, annotation.shape)
        XCTAssertEqual(doc.annotations.count, 1)
    }

    func testUpdateIsNoOpWhenAnnotationAbsent() {
        var doc = Document(source: source(), scaleFactor: 1)
        doc.update(rectAnnotation())
        XCTAssertTrue(doc.annotations.isEmpty)
    }

    func testRemoveDeletesAnnotationById() {
        var doc = Document(source: source(), scaleFactor: 1)
        let annotation = rectAnnotation()
        doc.add(annotation)
        doc.remove(id: annotation.id)
        XCTAssertNil(doc.annotation(id: annotation.id))
        XCTAssertTrue(doc.annotations.isEmpty)
    }

    func testBringToFrontMovesAnnotationToTheEndOfTheArray() {
        var doc = Document(source: source(), scaleFactor: 1)
        let a = rectAnnotation(1)
        let b = rectAnnotation(2)
        let c = rectAnnotation(3)
        doc.add(a)
        doc.add(b)
        doc.add(c)
        doc.bringToFront(id: a.id)
        XCTAssertEqual(doc.annotations.map(\.id), [b.id, c.id, a.id])
    }

    // MARK: normalizeSteps / nextStepNumber

    func testNormalizeStepsRenumbersAfterRemovingTheMiddleStep() {
        var doc = Document(source: source(), scaleFactor: 1)
        let s1 = Annotation(shape: .step(center: CGPoint(x: 0, y: 0), number: 1), style: style())
        let s2 = Annotation(shape: .step(center: CGPoint(x: 10, y: 10), number: 2), style: style())
        let s3 = Annotation(shape: .step(center: CGPoint(x: 20, y: 20), number: 3), style: style())
        doc.add(s1)
        doc.add(s2)
        doc.add(s3)
        doc.remove(id: s2.id)
        let numbers: [Int] = doc.annotations.compactMap {
            if case .step(_, let number) = $0.shape { return number }
            return nil
        }
        XCTAssertEqual(numbers, [1, 2])
    }

    func testAddNormalizesAnOutOfOrderStepNumber() {
        var doc = Document(source: source(), scaleFactor: 1)
        doc.add(Annotation(shape: .step(center: .zero, number: 99), style: style()))
        guard case .step(_, let number) = doc.annotations[0].shape else { return XCTFail("expected a step") }
        XCTAssertEqual(number, 1)
    }

    func testNextStepNumber() {
        var doc = Document(source: source(), scaleFactor: 1)
        XCTAssertEqual(doc.nextStepNumber, 1)
        doc.add(Annotation(shape: .step(center: .zero, number: 1), style: style()))
        XCTAssertEqual(doc.nextStepNumber, 2)
        doc.add(rectAnnotation())
        XCTAssertEqual(doc.nextStepNumber, 2)
    }

    // MARK: effectiveCrop

    func testEffectiveCropIsFullImageWhenCropRectIsNil() {
        let doc = Document(source: source(), scaleFactor: 1)
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    func testEffectiveCropClampsToImageBoundsAndRoundsToIntegers() {
        var doc = Document(source: source(), scaleFactor: 1)
        doc.cropRect = CGRect(x: -10, y: -5, width: 50.6, height: 40.4)
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: 0, y: 0, width: 41, height: 36))
    }

    func testEffectiveCropClampsOnTheFarEdgeAndRoundsToIntegers() {
        var doc = Document(source: source(), scaleFactor: 1)
        doc.cropRect = CGRect(x: 60.5, y: 50.5, width: 60, height: 60)
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: 60, y: 50, width: 40, height: 30))
    }

    func testEffectiveCropFallsBackToFullImageWhenCropRectDoesNotIntersect() {
        var doc = Document(source: source(), scaleFactor: 1)
        doc.cropRect = CGRect(x: 200, y: 200, width: 10, height: 10)
        XCTAssertEqual(doc.effectiveCrop, CGRect(x: 0, y: 0, width: 100, height: 80))
    }

    // MARK: Equatable

    func testDocumentsWithTheSameSourceAreEqualWhenStateMatches() {
        let image = source()
        var a = Document(source: image, scaleFactor: 1)
        var b = Document(source: image, scaleFactor: 1)
        XCTAssertEqual(a, b)
        a.add(rectAnnotation())
        XCTAssertNotEqual(a, b)
        b.add(a.annotations[0])
        XCTAssertEqual(a, b)
    }

    func testDocumentsWithDifferentSourceInstancesAreNotEqual() {
        let a = Document(source: source(), scaleFactor: 1)
        let b = Document(source: source(), scaleFactor: 1)
        XCTAssertNotEqual(a, b)
    }
}
