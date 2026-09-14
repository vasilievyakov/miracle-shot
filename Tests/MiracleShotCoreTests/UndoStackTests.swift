import XCTest
@testable import MiracleShotCore

final class UndoStackTests: XCTestCase {
    func testCanUndoAndCanRedoReflectStackState() {
        var stack = UndoStack<Int>()
        XCTAssertFalse(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
        stack.push(1)
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func testUndoOnEmptyStackReturnsNil() {
        var stack = UndoStack<Int>()
        XCTAssertNil(stack.undo(current: 5))
    }

    func testRedoOnEmptyStackReturnsNil() {
        var stack = UndoStack<Int>()
        XCTAssertNil(stack.redo(current: 5))
    }

    func testPushUndoRedoRoundTrip() {
        var stack = UndoStack<Int>()
        stack.push(0)
        let undone = stack.undo(current: 1)
        XCTAssertEqual(undone, 0)
        XCTAssertFalse(stack.canUndo)
        XCTAssertTrue(stack.canRedo)

        let redone = stack.redo(current: undone!)
        XCTAssertEqual(redone, 1)
        XCTAssertTrue(stack.canUndo)
        XCTAssertFalse(stack.canRedo)
    }

    func testPushClearsRedo() {
        var stack = UndoStack<Int>()
        stack.push(0)
        _ = stack.undo(current: 1)
        XCTAssertTrue(stack.canRedo)

        stack.push(2)
        XCTAssertFalse(stack.canRedo)
        XCTAssertTrue(stack.canUndo)
    }

    func testLimitDropsTheOldestEntry() {
        var stack = UndoStack<Int>(limit: 3)
        for i in 0..<5 {
            stack.push(i)
        }
        XCTAssertEqual(stack.undoStates, [2, 3, 4])
    }
}
