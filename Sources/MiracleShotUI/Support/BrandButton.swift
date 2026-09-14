import AppKit
import MiracleShotCore

/// Flat button on ink3 with bone text. Keyboard focus ring off; hover turns the text lime.
@MainActor
final class BrandButton: NSButton {
    private var tracking: NSTrackingArea?

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = BrandPalette.ink3.cgColor()
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = BrandPalette.line.cgColor()
        font = .systemFont(ofSize: 12, weight: .medium)
        setTitleColor(BrandPalette.bone)
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func setTitleColor(_ color: BrandColor) {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color.nsColor(), .font: font ?? .systemFont(ofSize: 12, weight: .medium),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { setTitleColor(BrandPalette.lime) } }
    override func mouseExited(with event: NSEvent) { setTitleColor(BrandPalette.bone) }
}
