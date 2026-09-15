import XCTest
@testable import MiracleShotCore

final class EditorSessionTests: XCTestCase {
    // MARK: Fixtures

    private func source(width: Int = 200, height: Int = 200) -> CGImage {
        TestImages.solid(width: width, height: height, r: 1, g: 1, b: 1)
    }

    private func makeDocument(width: Int = 200, height: Int = 200) -> Document {
        Document(source: source(width: width, height: height), scaleFactor: 1)
    }

    /// A fixed box for text so no font metrics are needed, per the task's testing guidance.
    private let fixedBounds: @Sendable (Annotation) -> CGRect = { annotation in
        if case .text(let origin, let string) = annotation.shape {
            return CGRect(x: origin.x, y: origin.y, width: max(CGFloat(string.count) * 10, 10), height: 20)
        }
        return annotation.geometryBounds
    }

    private func makeSession(document: Document? = nil) -> EditorSession {
        var session = EditorSession(document: document ?? makeDocument(), style: AnnotationStyle(), bounds: fixedBounds)
        session.hitTolerance = 4
        session.handleTolerance = 4
        return session
    }

    // MARK: Shape tools: mouseDown starts .drawing at a degenerate shape

    func testRectToolMouseDownStartsDrawingWithADegenerateShape() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        guard case .drawing(let annotation) = session.transient else { return XCTFail("expected a drawing transient") }
        guard case .rect(let rect) = annotation.shape else { return XCTFail("expected a rect") }
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 0, height: 0))
        XCTAssertTrue(session.document.annotations.isEmpty, "nothing is added to the document until commit")
    }

    func testDragToolsUpdateTheFarPointAndStandardizeTheRect() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 50, y: 50), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 20, y: 10)))
        guard case .drawing(let annotation) = session.transient else { return XCTFail("expected a drawing transient") }
        guard case .rect(let rect) = annotation.shape else { return XCTFail("expected a rect") }
        // Dragging up and to the left of the anchor standardizes to a rect with origin at the drag point.
        XCTAssertEqual(rect, CGRect(x: 20, y: 10, width: 30, height: 40))
    }

    func testShapeToolsIgnoreTheCurrentSelectionAndAlwaysStartDrawing() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 40, y: 40), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 80, y: 80)))
        session.handle(.mouseUp(CGPoint(x: 80, y: 80)))

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 60, y: 60), shift: false))
        session.handle(.mouseUp(CGPoint(x: 60, y: 60)))
        XCTAssertNotNil(session.selectedID, "the rect should now be selected")

        session.tool = .ellipse
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        guard case .drawing = session.transient else { return XCTFail("expected drawing to start regardless of selection") }
    }

    // MARK: Commit thresholds

    func testRectCommitsWhenLargerThan3PxInBothDimensions() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 15, y: 15)))
        session.handle(.mouseUp(CGPoint(x: 15, y: 15)))
        XCTAssertEqual(session.document.annotations.count, 1)
        XCTAssertNil(session.transient)
        XCTAssertEqual(session.selectedID, session.document.annotations.first?.id)
        XCTAssertTrue(session.canUndo)
    }

    func testRectDiscardsWhenNotLargerThan3Px() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 12, y: 12)))
        session.handle(.mouseUp(CGPoint(x: 12, y: 12)))
        XCTAssertTrue(session.document.annotations.isEmpty)
        XCTAssertNil(session.transient)
        XCTAssertFalse(session.canUndo)
    }

    func testLineCommitsWhenLongerThan3Px() {
        var session = makeSession()
        session.tool = .line
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 10, y: 15)))
        session.handle(.mouseUp(CGPoint(x: 10, y: 15)))
        XCTAssertEqual(session.document.annotations.count, 1)
    }

    func testLineDiscardsWhenNotLongerThan3Px() {
        var session = makeSession()
        session.tool = .line
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 11, y: 11)))
        session.handle(.mouseUp(CGPoint(x: 11, y: 11)))
        XCTAssertTrue(session.document.annotations.isEmpty)
    }

    func testArrowDrawingTracksTheDragPointKeepingTheAnchorFixed() {
        var session = makeSession()
        session.tool = .arrow
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 90, y: 40)))
        guard case .drawing(let annotation) = session.transient else { return XCTFail("expected a drawing transient") }
        guard case .arrow(let from, let to) = annotation.shape else { return XCTFail("expected an arrow") }
        XCTAssertEqual(from, CGPoint(x: 10, y: 10))
        XCTAssertEqual(to, CGPoint(x: 90, y: 40))
    }

    func testBlurToolUsesTheCurrentBlurModeAndCommits() {
        var session = makeSession()
        session.tool = .blur
        session.blurMode = .pixelate
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 30, y: 30)))
        session.handle(.mouseUp(CGPoint(x: 30, y: 30)))
        guard case .blur(_, let mode) = session.document.annotations.first?.shape else { return XCTFail("expected a blur annotation") }
        XCTAssertEqual(mode, .pixelate)
    }

    func testHighlightToolCommits() {
        var session = makeSession()
        session.tool = .highlight
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 30, y: 30)))
        session.handle(.mouseUp(CGPoint(x: 30, y: 30)))
        XCTAssertEqual(session.document.annotations.count, 1)
    }

    func testFreehandAppendsPointsOnDrag() {
        var session = makeSession()
        session.tool = .freehand
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 12, y: 12)))
        session.handle(.mouseDragged(CGPoint(x: 14, y: 14)))
        guard case .drawing(let annotation) = session.transient else { return XCTFail("expected a drawing transient") }
        guard case .freehand(let points) = annotation.shape else { return XCTFail("expected freehand") }
        XCTAssertEqual(points, [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 12), CGPoint(x: 14, y: 14)])
    }

    func testFreehandCommitsWithAtLeastTwoPoints() {
        var session = makeSession()
        session.tool = .freehand
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 12, y: 12)))
        session.handle(.mouseUp(CGPoint(x: 12, y: 12)))
        XCTAssertEqual(session.document.annotations.count, 1)
    }

    func testFreehandDiscardsWithOnlyOnePoint() {
        var session = makeSession()
        session.tool = .freehand
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseUp(CGPoint(x: 10, y: 10)))
        XCTAssertTrue(session.document.annotations.isEmpty)
    }

    func testDrawingCommitPushesUndoSelectsTheNewAnnotationAndKeepsTheTool() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 30, y: 30)))
        session.handle(.mouseUp(CGPoint(x: 30, y: 30)))
        XCTAssertEqual(session.tool, .rect)
        XCTAssertEqual(session.selectedID, session.document.annotations.first?.id)
        XCTAssertEqual(session.undo.undoStates.count, 1)
    }

    // MARK: Text

    func testTextToolMouseDownCreatesAnEmptyAnnotationSelectsItAndBeginsEditing() {
        var session = makeSession()
        session.tool = .text
        let effect = session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        guard let annotation = session.document.annotations.first else { return XCTFail("expected an annotation") }
        guard case .text(let origin, let string) = annotation.shape else { return XCTFail("expected text") }
        XCTAssertEqual(origin, CGPoint(x: 30, y: 40))
        XCTAssertEqual(string, "")
        XCTAssertEqual(session.selectedID, annotation.id)
        XCTAssertEqual(effect, .beginTextEditing(id: annotation.id))
        // Nothing is pushed until we know whether the text sticks.
        XCTAssertFalse(session.canUndo)
    }

    func testTextCommittedWithANonEmptyStringUpdatesTheAnnotationAndPushesUndo() {
        var session = makeSession()
        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations[0].id
        let effect = session.handle(.textCommitted(id: id, string: "hello"))
        XCTAssertEqual(effect, .endTextEditing)
        guard case .text(_, let string) = session.document.annotation(id: id)?.shape else { return XCTFail("expected text") }
        XCTAssertEqual(string, "hello")
        XCTAssertTrue(session.canUndo)
        XCTAssertEqual(session.undo.undoStates.count, 1)
    }

    func testTextCommittedWithAnEmptyStringRemovesANewlyCreatedAnnotationAndDropsTheUndoEntry() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 5, y: 5), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        XCTAssertEqual(session.undo.undoStates.count, 1, "one real action happened before the text creation")

        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations.last!.id
        XCTAssertEqual(session.document.annotations.count, 2)

        let effect = session.handle(.textCommitted(id: id, string: ""))
        XCTAssertEqual(effect, .endTextEditing)
        XCTAssertEqual(session.document.annotations.count, 1, "the empty text annotation is gone")
        XCTAssertNil(session.selectedID)
        XCTAssertEqual(session.undo.undoStates.count, 1, "no undo entry was added by the text creation attempt")
    }

    func testTextCancelledRemovesANewlyCreatedAnnotationAndDropsTheUndoEntry() {
        var session = makeSession()
        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations[0].id

        let effect = session.handle(.textCancelled(id: id))
        XCTAssertEqual(effect, .endTextEditing)
        XCTAssertTrue(session.document.annotations.isEmpty)
        XCTAssertNil(session.selectedID)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    // MARK: editText (re-opening an existing text annotation)

    func testEditTextOnAnExistingTextAnnotationBeginsEditing() {
        var session = makeSession()
        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations[0].id
        session.handle(.textCommitted(id: id, string: "hello"))

        let effect = session.handle(.editText(id: id))
        XCTAssertEqual(effect, .beginTextEditing(id: id))
        XCTAssertEqual(session.selectedID, id)
    }

    func testEditTextCommittedPushesUndoOnlyWhenTheStringChanged() {
        var session = makeSession()
        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations[0].id
        session.handle(.textCommitted(id: id, string: "hello"))
        XCTAssertEqual(session.undo.undoStates.count, 1)

        session.handle(.editText(id: id))
        session.handle(.textCommitted(id: id, string: "goodbye"))
        XCTAssertEqual(session.undo.undoStates.count, 2, "the string changed, so a new undo entry was pushed")
        guard case .text(_, let string) = session.document.annotation(id: id)?.shape else { return XCTFail("expected text") }
        XCTAssertEqual(string, "goodbye")
    }

    func testEditTextCommittedWithAnUnchangedStringPushesNothing() {
        var session = makeSession()
        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations[0].id
        session.handle(.textCommitted(id: id, string: "hello"))
        XCTAssertEqual(session.undo.undoStates.count, 1)

        session.handle(.editText(id: id))
        session.handle(.textCommitted(id: id, string: "hello"))
        XCTAssertEqual(session.undo.undoStates.count, 1, "an unchanged commit pushes nothing")
    }

    func testEditTextCancelledLeavesTheAnnotationAsItWas() {
        var session = makeSession()
        session.tool = .text
        session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        let id = session.document.annotations[0].id
        session.handle(.textCommitted(id: id, string: "hello"))
        let before = session.document

        session.handle(.editText(id: id))
        let effect = session.handle(.textCancelled(id: id))
        XCTAssertEqual(effect, .endTextEditing)
        XCTAssertEqual(session.document, before)
    }

    // MARK: Step

    func testStepToolMouseDownAddsANumberedStepImmediatelyAndPushesUndo() {
        var session = makeSession()
        session.tool = .step
        let effect = session.handle(.mouseDown(CGPoint(x: 30, y: 40), shift: false))
        XCTAssertNil(effect)
        guard case .step(let center, let number) = session.document.annotations.first?.shape else { return XCTFail("expected a step") }
        XCTAssertEqual(center, CGPoint(x: 30, y: 40))
        XCTAssertEqual(number, 1)
        XCTAssertEqual(session.selectedID, session.document.annotations[0].id)
        XCTAssertTrue(session.canUndo)
        XCTAssertNil(session.transient, "steps do not drag")
    }

    func testStepNumberingRenumbersAfterDeletingTheFirstOfTwo() {
        var session = makeSession()
        session.tool = .step
        session.handle(.mouseDown(CGPoint(x: 20, y: 20), shift: false))
        session.handle(.mouseDown(CGPoint(x: 120, y: 120), shift: false))
        XCTAssertEqual(session.document.annotations.count, 2)

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 20, y: 20), shift: false))
        session.handle(.mouseUp(CGPoint(x: 20, y: 20)))
        session.handle(.deleteSelection)

        guard case .step(_, let remainingNumber) = session.document.annotations.first?.shape else { return XCTFail("expected a step") }
        XCTAssertEqual(remainingNumber, 1)
    }

    // MARK: Select tool

    func testSelectMouseDownOnAnAnnotationSelectsItAndStartsMoving() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let id = session.document.annotations[0].id

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 30, y: 30), shift: false))
        XCTAssertEqual(session.selectedID, id)
        guard case .moving(let movingID, _) = session.transient else { return XCTFail("expected a moving transient") }
        XCTAssertEqual(movingID, id)
    }

    func testSelectMouseDownOnEmptySpaceClearsSelection() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        XCTAssertNotNil(session.selectedID)

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 150, y: 150), shift: false))
        XCTAssertNil(session.selectedID)
        XCTAssertNil(session.transient)
    }

    func testSelectMouseDownOnAHandleOfTheSelectionStartsResizingInsteadOfMoving() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let id = session.document.annotations[0].id
        session.tool = .select

        // The bottomRight handle sits at (50, 50); clicking there should resize, not move, even though
        // the point is also inside the annotation.
        session.handle(.mouseDown(CGPoint(x: 50, y: 50), shift: false))
        guard case .resizing(let resizingID, let handle) = session.transient else { return XCTFail("expected a resizing transient") }
        XCTAssertEqual(resizingID, id)
        XCTAssertEqual(handle, .bottomRight)
    }

    func testMovingAppliesTheDeltaLiveAndPushesUndoOnceForAMultiDrag() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let id = session.document.annotations[0].id
        let undoCountBefore = session.undo.undoStates.count

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 30, y: 30), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 40, y: 30)))
        session.handle(.mouseDragged(CGPoint(x: 60, y: 30)))
        session.handle(.mouseDragged(CGPoint(x: 70, y: 40)))
        session.handle(.mouseUp(CGPoint(x: 70, y: 40)))

        XCTAssertEqual(session.undo.undoStates.count, undoCountBefore + 1, "exactly one undo entry for the whole drag")
        guard case .rect(let rect) = session.document.annotation(id: id)?.shape else { return XCTFail("expected a rect") }
        // Original rect (10,10)-(50,50) shifted by the total delta (60, 30): dx = 70-30 = 40, dy = 40-30 = 10.
        XCTAssertEqual(rect, CGRect(x: 50, y: 20, width: 40, height: 40))
    }

    func testMovingWithoutADragPushesNothing() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let undoCountBefore = session.undo.undoStates.count

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 30, y: 30), shift: false))
        session.handle(.mouseUp(CGPoint(x: 30, y: 30)))
        XCTAssertEqual(session.undo.undoStates.count, undoCountBefore, "a click without a drag pushes nothing")
    }

    func testResizingAppliesLiveAndPushesUndoOnce() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let id = session.document.annotations[0].id
        let undoCountBefore = session.undo.undoStates.count

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 50, y: 50), shift: false))   // bottomRight handle
        session.handle(.mouseDragged(CGPoint(x: 80, y: 60)))
        session.handle(.mouseDragged(CGPoint(x: 90, y: 70)))
        session.handle(.mouseUp(CGPoint(x: 90, y: 70)))

        XCTAssertEqual(session.undo.undoStates.count, undoCountBefore + 1)
        guard case .rect(let rect) = session.document.annotation(id: id)?.shape else { return XCTFail("expected a rect") }
        XCTAssertEqual(rect, CGRect(x: 10, y: 10, width: 80, height: 60))
    }

    func testResizingWithoutADragPushesNothing() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let undoCountBefore = session.undo.undoStates.count

        session.tool = .select
        session.handle(.mouseDown(CGPoint(x: 50, y: 50), shift: false))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        XCTAssertEqual(session.undo.undoStates.count, undoCountBefore)
    }

    // MARK: Crop

    func testSelectingCropToolInitializesPendingCropToTheFullImageWhenThereIsNoCrop() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        XCTAssertEqual(session.pendingCrop, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    func testSelectingCropToolInitializesPendingCropToTheExistingCropRect() {
        var document = makeDocument(width: 200, height: 100)
        document.cropRect = CGRect(x: 10, y: 10, width: 50, height: 50)
        var session = makeSession(document: document)
        session.handle(.selectTool(.crop))
        XCTAssertEqual(session.pendingCrop, CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    func testCropDragSetsAStandardizedRectClampedToTheImage() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        session.handle(.mouseDown(CGPoint(x: 50, y: 50), shift: false))
        session.handle(.mouseDragged(CGPoint(x: -20, y: 300)))
        guard case .cropping(let anchor, let rect) = session.transient else { return XCTFail("expected a cropping transient") }
        XCTAssertEqual(anchor, CGPoint(x: 50, y: 50))
        XCTAssertEqual(rect, CGRect(x: 0, y: 50, width: 50, height: 50))
    }

    func testCropMouseUpKeepsPendingCropWhenLargerThan8x8() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 60, y: 60)))
        session.handle(.mouseUp(CGPoint(x: 60, y: 60)))
        XCTAssertEqual(session.pendingCrop, CGRect(x: 10, y: 10, width: 50, height: 50))
        XCTAssertNil(session.transient)
    }

    func testCropMouseUpDiscardsATooSmallDragKeepingThePreviousPendingCrop() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        let initialPendingCrop = session.pendingCrop
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 13, y: 13)))
        session.handle(.mouseUp(CGPoint(x: 13, y: 13)))
        XCTAssertEqual(session.pendingCrop, initialPendingCrop)
    }

    func testCropConfirmPushesUndoSetsCropRectAndSwitchesToSelect() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 60, y: 60)))
        session.handle(.mouseUp(CGPoint(x: 60, y: 60)))

        session.handle(.cropConfirm)
        XCTAssertEqual(session.document.cropRect, CGRect(x: 10, y: 10, width: 50, height: 50))
        XCTAssertEqual(session.tool, .select)
        XCTAssertNil(session.pendingCrop)
        XCTAssertTrue(session.canUndo)
    }

    func testCropConfirmSetsCropRectToNilWhenItEqualsTheFullImage() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        session.handle(.cropConfirm)
        XCTAssertNil(session.document.cropRect)
        XCTAssertEqual(session.tool, .select)
    }

    func testCropCancelDiscardsPendingCropAndSwitchesToSelect() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 60, y: 60)))
        session.handle(.mouseUp(CGPoint(x: 60, y: 60)))

        session.handle(.cropCancel)
        XCTAssertNil(session.pendingCrop)
        XCTAssertEqual(session.tool, .select)
        XCTAssertNil(session.document.cropRect)
        XCTAssertFalse(session.canUndo)
    }

    func testEscapeWhileCroppingDiscardsPendingCropAndSwitchesToSelect() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 60, y: 60)))

        session.handle(.escape)
        XCTAssertNil(session.pendingCrop)
        XCTAssertNil(session.transient)
        XCTAssertEqual(session.tool, .select)
    }

    func testSelectingAnotherToolAwayFromCropDiscardsThePendingCrop() {
        var session = makeSession(document: makeDocument(width: 200, height: 100))
        session.handle(.selectTool(.crop))
        XCTAssertNotNil(session.pendingCrop)
        session.handle(.selectTool(.rect))
        XCTAssertNil(session.pendingCrop)
        XCTAssertEqual(session.tool, .rect)
    }

    // MARK: deleteSelection

    func testDeleteSelectionPushesUndoAndRemovesTheAnnotation() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let undoCountBefore = session.undo.undoStates.count

        session.handle(.deleteSelection)
        XCTAssertTrue(session.document.annotations.isEmpty)
        XCTAssertNil(session.selectedID)
        XCTAssertEqual(session.undo.undoStates.count, undoCountBefore + 1)
    }

    func testDeleteSelectionIsNoOpWithoutASelection() {
        var session = makeSession()
        session.handle(.deleteSelection)
        XCTAssertFalse(session.canUndo)
    }

    // MARK: setStyle

    func testSetStyleBecomesTheCurrentStyle() {
        var session = makeSession()
        let newStyle = AnnotationStyle(strokeColor: BrandPalette.coral, lineWidth: 8)
        session.handle(.setStyle(newStyle))
        XCTAssertEqual(session.style, newStyle)
    }

    func testSetStyleWithASelectionPushesUndoAndUpdatesItsStyle() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        let id = session.document.annotations[0].id
        let undoCountBefore = session.undo.undoStates.count

        let newStyle = AnnotationStyle(strokeColor: BrandPalette.coral, lineWidth: 8)
        session.handle(.setStyle(newStyle))
        XCTAssertEqual(session.document.annotation(id: id)?.style, newStyle)
        XCTAssertEqual(session.undo.undoStates.count, undoCountBefore + 1)
    }

    // MARK: setBackground

    func testSetBackgroundPushesUndoAndSetsTheBackground() {
        var session = makeSession()
        let preset = BackgroundPreset(id: "test", name: "Test", fill: .solid(color: BrandPalette.bone),
                                       paddingPercent: 10, cornerRadiusPercent: 0, shadow: nil)
        session.handle(.setBackground(preset))
        XCTAssertEqual(session.document.background, preset)
        XCTAssertTrue(session.canUndo)
    }

    // MARK: undo/redo

    func testUndoRestoresThePreviousDocumentAndClearsSelection() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        XCTAssertEqual(session.document.annotations.count, 1)

        session.handle(.undo)
        XCTAssertTrue(session.document.annotations.isEmpty)
        XCTAssertNil(session.selectedID)
        XCTAssertNil(session.transient)
        XCTAssertTrue(session.canRedo)
    }

    func testRedoReappliesTheDocumentAndClearsSelection() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        session.handle(.undo)

        session.handle(.redo)
        XCTAssertEqual(session.document.annotations.count, 1)
        XCTAssertNil(session.selectedID, "redo clears the selection too")
        XCTAssertFalse(session.canRedo)
    }

    // MARK: escape

    func testEscapeCancelsAnInProgressDrawingWithoutCommitting() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))

        session.handle(.escape)
        XCTAssertNil(session.transient)
        XCTAssertTrue(session.document.annotations.isEmpty)
        XCTAssertEqual(session.tool, .rect, "the tool itself is not reset")
        XCTAssertFalse(session.canUndo)
    }

    func testEscapeClearsSelectionWhenNothingIsInProgress() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        XCTAssertNotNil(session.selectedID)

        session.handle(.escape)
        XCTAssertNil(session.selectedID)
    }

    // MARK: displayAnnotations

    func testDisplayAnnotationsIncludesTheInProgressShape() {
        var session = makeSession()
        session.tool = .rect
        session.handle(.mouseDown(CGPoint(x: 10, y: 10), shift: false))
        session.handle(.mouseDragged(CGPoint(x: 50, y: 50)))
        XCTAssertEqual(session.document.annotations.count, 0)
        XCTAssertEqual(session.displayAnnotations.count, 1)

        session.handle(.mouseUp(CGPoint(x: 50, y: 50)))
        XCTAssertEqual(session.displayAnnotations.count, 1)
        XCTAssertEqual(session.displayAnnotations, session.document.annotations)
    }
}
