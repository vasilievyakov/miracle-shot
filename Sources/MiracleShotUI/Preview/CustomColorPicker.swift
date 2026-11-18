import AppKit
import MiracleShotCore

/// "Custom Color…" from the Background menu: the shared system color panel with an accessory row (a "Save as
/// preset" checkbox and an Apply button). Apply hands the color to the callback in sRGB, rounded to `#rrggbb` so the
/// applied backdrop and a saved preset are the same color, and closes the panel. Closing without Apply does nothing.
@MainActor
final class CustomColorPicker: NSObject {
    typealias Completion = @MainActor (_ color: BrandColor, _ save: Bool) -> Void

    private var completion: Completion?
    private var closeObserver: NSObjectProtocol?
    private let saveCheckbox = NSButton(checkboxWithTitle: "Save as preset", target: nil, action: nil)
    private lazy var accessory: NSView = makeAccessory()

    func present(completion: @escaping Completion) {
        self.completion = completion
        saveCheckbox.state = .off
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.accessoryView = accessory
        if closeObserver == nil {
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel,
                                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reset() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func applyTapped(_ sender: NSButton) {
        guard let rgb = NSColorPanel.shared.color.usingColorSpace(.sRGB) else { return }
        let clamp = { (value: CGFloat) in min(max(value, 0), 1) }
        let exact = BrandColor(red: clamp(rgb.redComponent), green: clamp(rgb.greenComponent), blue: clamp(rgb.blueComponent))
        let color = BrandColor(hex: exact.hex) ?? exact
        let save = saveCheckbox.state == .on
        let completion = self.completion
        NSColorPanel.shared.close()   // fires willClose, which resets the panel
        completion?(color, save)
    }

    private func reset() {
        completion = nil
        if NSColorPanel.shared.accessoryView === accessory { NSColorPanel.shared.accessoryView = nil }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
    }

    private func makeAccessory() -> NSView {
        let apply = NSButton(title: "Apply", target: self, action: #selector(applyTapped(_:)))
        apply.keyEquivalent = "\r"
        let row = NSStackView(views: [saveCheckbox, NSView(), apply])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        row.frame = NSRect(x: 0, y: 0, width: 240, height: 40)
        row.autoresizingMask = [.width]
        return row
    }
}
