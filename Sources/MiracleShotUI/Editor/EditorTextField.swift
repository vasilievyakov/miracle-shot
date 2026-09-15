import AppKit
import MiracleShotCore

/// Borderless inline editor for a text annotation: Onest, lime text on ink2, grows with its content.
/// Enter commits, Escape cancels; `EditorCanvasView` positions it, makes it first responder and removes it.
@MainActor
final class EditorTextField: NSTextField, NSTextFieldDelegate {
    private static let minimumWidth: CGFloat = 40

    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(text: String, fontSize: CGFloat, scale: CGFloat) {
        super.init(frame: .zero)
        isBordered = false
        isBezeled = false
        drawsBackground = true
        backgroundColor = BrandPalette.ink2.nsColor()
        textColor = BrandPalette.lime.nsColor()
        font = BrandFont.text(size: fontSize * scale, weight: 600)
        focusRingType = .none
        delegate = self
        stringValue = text
        sizeToFitContent()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Resizes to fit the current string, never narrower than `minimumWidth`; keeps `frame.origin`.
    private func sizeToFitContent() {
        sizeToFit()
        var frame = self.frame
        frame.size.width = max(frame.size.width, Self.minimumWidth)
        self.frame = frame
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            resolve { onCommit?(stringValue) }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            resolve { onCancel?() }
            return true
        }
        return false
    }

    /// Clicking elsewhere ends editing without Enter; keep what was typed instead of losing it.
    func controlTextDidEndEditing(_ obj: Notification) {
        resolve { onCommit?(stringValue) }
    }

    /// Enter, Escape and focus loss can all fire for one edit; only the first one counts.
    private var resolved = false

    private func resolve(_ action: () -> Void) {
        guard !resolved else { return }
        resolved = true
        action()
    }

    func controlTextDidChange(_ obj: Notification) {
        sizeToFitContent()
    }
}
