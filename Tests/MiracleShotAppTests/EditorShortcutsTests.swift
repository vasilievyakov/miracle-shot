import AppKit
import MiracleShotCore
import XCTest
@testable import MiracleShotUI

final class EditorShortcutsTests: XCTestCase {
    func testToolLetters() {
        let expected: [(key: String, tool: Tool)] = [
            ("v", .select), ("a", .arrow), ("l", .line), ("r", .rect), ("o", .ellipse),
            ("p", .freehand), ("t", .text), ("n", .step), ("b", .blur), ("h", .highlight), ("c", .crop),
        ]
        for (key, tool) in expected {
            XCTAssertEqual(EditorShortcuts.event(forKey: key, modifiers: [], cropActive: false), .selectTool(tool), "key \(key)")
        }
    }

    func testUndo() {
        XCTAssertEqual(EditorShortcuts.event(forKey: "z", modifiers: .command, cropActive: false), .undo)
    }

    func testRedo() {
        XCTAssertEqual(EditorShortcuts.event(forKey: "z", modifiers: [.command, .shift], cropActive: false), .redo)
    }

    func testDelete() {
        XCTAssertEqual(EditorShortcuts.event(forKey: "\u{7f}", modifiers: [], cropActive: false), .deleteSelection)
    }

    func testBackspace() {
        XCTAssertEqual(EditorShortcuts.event(forKey: "\u{8}", modifiers: [], cropActive: false), .deleteSelection)
    }

    func testEscape() {
        XCTAssertEqual(EditorShortcuts.event(forKey: "\u{1b}", modifiers: [], cropActive: false), .escape)
    }

    func testReturnConfirmsCropOnlyWhenActive() {
        XCTAssertEqual(EditorShortcuts.event(forKey: "\r", modifiers: [], cropActive: true), .cropConfirm)
        XCTAssertNil(EditorShortcuts.event(forKey: "\r", modifiers: [], cropActive: false))
    }

    func testUnmappedKeyIsNil() {
        XCTAssertNil(EditorShortcuts.event(forKey: "q", modifiers: [], cropActive: false))
    }

    func testToolLetterWithCommandIsNotAShortcut() {
        XCTAssertNil(EditorShortcuts.event(forKey: "v", modifiers: .command, cropActive: false))
    }

    func testPlainZWithoutCommandIsNotUndo() {
        XCTAssertNil(EditorShortcuts.event(forKey: "z", modifiers: [], cropActive: false))
    }
}
