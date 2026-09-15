import AppKit
import MiracleShotCore

/// Flat button on ink3 with bone text, or an icon-only tool button showing a template SF Symbol. Keyboard focus
/// ring off; hover turns title text lime. `isActive` (the current tool, swatch, width or crop/blur state) turns
/// the border and the icon tint (or title text) lime.
@MainActor
final class BrandButton: NSButton {
    private var tracking: NSTrackingArea?

    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            applyActiveStyle()
        }
    }

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        configureChrome()
        self.title = title
        self.target = target
        self.action = action
        font = BrandFont.text(size: 12, weight: 500)
        setTitleColor(BrandPalette.bone)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }

    /// Icon-only tool button for the editor toolbar: a template SF Symbol image, tinted bone (lime when `isActive`).
    init(symbol: String, accessibilityLabel: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        configureChrome()
        self.target = target
        self.action = action
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(configuration)
        symbolImage?.isTemplate = true
        image = symbolImage
        imagePosition = .imageOnly
        contentTintColor = BrandPalette.bone.nsColor()
        setAccessibilityLabel(accessibilityLabel)
        widthAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Updates the visible label, keeping the current active/inactive text color (the blur mode toggle switches
    /// its title between "Blur" and "Pixels").
    func setLabel(_ newTitle: String) {
        title = newTitle
        setTitleColor(isActive ? BrandPalette.lime : BrandPalette.bone)
    }

    private func configureChrome() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = BrandPalette.ink3.cgColor()
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = BrandPalette.line.cgColor()
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func setTitleColor(_ color: BrandColor) {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color.nsColor(), .font: font ?? BrandFont.text(size: 12, weight: 500),
        ])
    }

    private func applyActiveStyle() {
        layer?.borderColor = (isActive ? BrandPalette.lime : BrandPalette.line).cgColor()
        if image != nil {
            contentTintColor = (isActive ? BrandPalette.lime : BrandPalette.bone).nsColor()
        } else {
            setTitleColor(isActive ? BrandPalette.lime : BrandPalette.bone)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled, image == nil { setTitleColor(BrandPalette.lime) } }
    override func mouseExited(with event: NSEvent) { if image == nil { setTitleColor(isActive ? BrandPalette.lime : BrandPalette.bone) } }
}
