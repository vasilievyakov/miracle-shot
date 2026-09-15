import AppKit
import MiracleShotCore

/// Pure key -> `EditorEvent` table for the editor window: letters select a tool, cmd+z / shift+cmd+z undo/redo,
/// delete/backspace remove the selection, escape cancels, return confirms an in-progress crop. Held separately
/// from any `NSEvent` handling so the mapping itself is testable without a window or a real key event.
enum EditorShortcuts {
    static func event(forKey key: String, modifiers: NSEvent.ModifierFlags, cropActive: Bool) -> EditorEvent? {
        let relevant = modifiers.intersection([.command, .option, .control, .shift])
        if relevant == [.command, .shift], key == "z" { return .redo }
        if relevant == .command, key == "z" { return .undo }
        guard relevant.isEmpty else { return nil }

        switch key {
        case "v": return .selectTool(.select)
        case "a": return .selectTool(.arrow)
        case "l": return .selectTool(.line)
        case "r": return .selectTool(.rect)
        case "o": return .selectTool(.ellipse)
        case "p": return .selectTool(.freehand)
        case "t": return .selectTool(.text)
        case "n": return .selectTool(.step)
        case "b": return .selectTool(.blur)
        case "h": return .selectTool(.highlight)
        case "c": return .selectTool(.crop)
        case "\u{7f}", "\u{8}": return .deleteSelection
        case "\u{1b}": return .escape
        case "\r": return cropActive ? .cropConfirm : nil
        default: return nil
        }
    }

    enum ZoomAction: Equatable {
        case zoomIn, zoomOut, fit, actualSize
    }

    /// Cmd+= / cmd++ zoom in, cmd+- zoom out, cmd+0 fit, cmd+1 actual size. Option/control rule a key out;
    /// shift is allowed through unchecked since it is what turns "=" into "+" on the way in.
    static func zoomAction(forKey key: String, modifiers: NSEvent.ModifierFlags) -> ZoomAction? {
        guard modifiers.intersection([.command, .option, .control]) == .command else { return nil }
        switch key {
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        case "0": return .fit
        case "1": return .actualSize
        default: return nil
        }
    }
}
