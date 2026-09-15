import AppKit
import MiracleShotCore

/// The editor's top bar: undo/redo, tools, style swatches and width, blur mode, background preset, export
/// (Copy/Done, or Apply/Cancel while cropping) and a drag handle. Purely a view: every action goes out through a
/// closure, and `refresh(from:)` is the only way state comes back in. `EditorWindowController` wires it to the
/// session and the window.
@MainActor
final class EditorToolbar: NSView {
    static let height: CGFloat = 44

    /// Fired for every tool/style/background change that maps onto an `EditorSession` event.
    var onEvent: ((EditorEvent) -> Void)?
    var onCopy: (() -> Void)?
    var onDone: (() -> Void)?
    var onCropApply: (() -> Void)?
    var onCropCancel: (() -> Void)?

    private static let toolSpecs: [(tool: Tool, symbol: String, label: String)] = [
        (.select, "cursorarrow", "Select"),
        (.arrow, "arrow.up.right", "Arrow"),
        (.line, "line.diagonal", "Line"),
        (.rect, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.freehand, "pencil", "Freehand"),
        (.text, "textformat", "Text"),
        (.step, "1.circle", "Numbered step"),
        (.blur, "drop.halffull", "Blur"),
        (.highlight, "highlighter", "Highlight"),
        (.crop, "crop", "Crop"),
    ]
    private static let swatchColors: [BrandColor] = [
        BrandPalette.lime, BrandPalette.coral, BrandPalette.bone, BrandPalette.boneDim, BrandPalette.ink,
    ]
    private static let widthLabels = ["S", "M", "L"]
    private static let lineWidths: [CGFloat] = [2, 4, 8]
    private static let fontSizes: [CGFloat] = [20, 28, 40]
    /// A style value within this many pixels of a width dot's own value counts as "the current one".
    private static let sizeMatchTolerance: CGFloat = 0.5

    private let presets: [BackgroundPreset]
    private var scaleFactor: CGFloat = 1
    private var currentTool: Tool = .select
    private var currentStyle = AnnotationStyle()
    private var currentBlurMode: BlurMode = .gaussian
    private var lastRenderedDocument: Document?

    private var toolButtons: [BrandButton] = []
    private var swatchButtons: [SwatchButton] = []
    private var widthButtons: [BrandButton] = []

    private let undoButton: BrandButton
    private let redoButton: BrandButton
    private let blurToggleButton: BrandButton
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let copyButton: BrandButton
    private let doneButton: BrandButton
    private let applyButton: BrandButton
    private let cancelButton: BrandButton
    private let dragHandle = DragHandleView()

    init(presets: [BackgroundPreset]) {
        self.presets = presets
        undoButton = BrandButton(symbol: "arrow.uturn.backward", accessibilityLabel: "Undo", target: nil, action: nil)
        redoButton = BrandButton(symbol: "arrow.uturn.forward", accessibilityLabel: "Redo", target: nil, action: nil)
        blurToggleButton = BrandButton(title: "Blur", target: nil, action: nil)
        copyButton = BrandButton(title: "Copy", target: nil, action: nil)
        doneButton = BrandButton(title: "Done", target: nil, action: nil)
        applyButton = BrandButton(title: "Apply", target: nil, action: nil)
        cancelButton = BrandButton(title: "Cancel", target: nil, action: nil)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = BrandPalette.ink2.cgColor()
        heightAnchor.constraint(equalToConstant: Self.height).isActive = true

        undoButton.target = self; undoButton.action = #selector(undoTapped(_:))
        redoButton.target = self; redoButton.action = #selector(redoTapped(_:))
        blurToggleButton.target = self; blurToggleButton.action = #selector(blurToggleTapped(_:))
        copyButton.target = self; copyButton.action = #selector(copyTapped(_:))
        doneButton.target = self; doneButton.action = #selector(doneTapped(_:))
        applyButton.target = self; applyButton.action = #selector(applyTapped(_:))
        cancelButton.target = self; cancelButton.action = #selector(cancelTapped(_:))

        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Layout

    private func buildLayout() {
        toolButtons = Self.toolSpecs.enumerated().map { index, spec in
            let button = BrandButton(symbol: spec.symbol, accessibilityLabel: spec.label, target: self, action: #selector(toolTapped(_:)))
            button.tag = index
            return button
        }
        swatchButtons = Self.swatchColors.map { color in
            SwatchButton(color: color, target: self, action: #selector(swatchTapped(_:)))
        }
        widthButtons = Self.widthLabels.enumerated().map { index, label in
            let button = BrandButton(title: label, target: self, action: #selector(widthTapped(_:)))
            button.tag = index
            return button
        }

        let toolStack = NSStackView(views: toolButtons)
        toolStack.orientation = .horizontal
        toolStack.spacing = 4

        let swatchStack = NSStackView(views: swatchButtons)
        swatchStack.orientation = .horizontal
        swatchStack.spacing = 6

        let widthStack = NSStackView(views: widthButtons)
        widthStack.orientation = .horizontal
        widthStack.spacing = 4

        let leftStack = NSStackView(views: [
            undoButton, redoButton, makeSeparator(),
            toolStack, makeSeparator(),
            swatchStack, makeSeparator(),
            widthStack, blurToggleButton,
        ])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 8
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        presetPopup.translatesAutoresizingMaskIntoConstraints = false
        presetPopup.addItem(withTitle: "None")
        for preset in presets { presetPopup.addItem(withTitle: preset.name) }
        presetPopup.target = self
        presetPopup.action = #selector(presetChosen(_:))

        let rightStack = NSStackView(views: [presetPopup, copyButton, doneButton, applyButton, cancelButton, dragHandle])
        rightStack.orientation = .horizontal
        rightStack.alignment = .centerY
        rightStack.spacing = 8
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftStack)
        addSubview(rightStack)
        addBottomBorder()

        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -8),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func makeSeparator() -> NSView {
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = BrandPalette.line.cgColor()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return separator
    }

    private func addBottomBorder() {
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = BrandPalette.line.cgColor()
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)
        NSLayoutConstraint.activate([
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: - State

    /// Refreshes every control from `session`: active tool, current color/width, undo/redo enabled, crop mode
    /// buttons, the blur toggle and the drag thumbnail.
    func refresh(from session: EditorSession) {
        scaleFactor = session.document.scaleFactor
        currentTool = session.tool
        currentStyle = session.style
        currentBlurMode = session.blurMode

        undoButton.isEnabled = session.canUndo
        redoButton.isEnabled = session.canRedo

        for (index, button) in toolButtons.enumerated() where Self.toolSpecs.indices.contains(index) {
            button.isActive = Self.toolSpecs[index].tool == session.tool
        }
        for button in swatchButtons {
            button.isCurrent = button.color == session.style.strokeColor
        }
        let values = sizeValues(for: session.tool)
        let current = session.tool == .text ? session.style.fontSize : session.style.lineWidth
        for (index, button) in widthButtons.enumerated() where values.indices.contains(index) {
            button.isActive = abs(values[index] - current) < Self.sizeMatchTolerance
        }

        let isBlurTool = session.tool == .blur
        blurToggleButton.isHidden = !isBlurTool
        blurToggleButton.setLabel(session.blurMode == .gaussian ? "Blur" : "Pixels")

        let isCropActive = session.tool == .crop
        copyButton.isHidden = isCropActive
        doneButton.isHidden = isCropActive
        applyButton.isHidden = !isCropActive
        cancelButton.isHidden = !isCropActive

        if let background = session.document.background, let index = presets.firstIndex(where: { $0.id == background.id }) {
            presetPopup.selectItem(at: index + 1)
        } else {
            presetPopup.selectItem(at: 0)
        }

        // A full render (blur goes through CoreImage) is too expensive per drag tick; only redo it when the
        // document itself changed.
        if lastRenderedDocument != session.document, let rendered = AnnotationRenderer.render(session.document) {
            lastRenderedDocument = session.document
            dragHandle.image = NSImage(cgImage: rendered, size: NSSize(width: 44, height: 28))
            dragHandle.renderProvider = { rendered }
        }
    }

    /// S/M/L values for the tool currently active: line width for every drawing tool, font size for text.
    private func sizeValues(for tool: Tool) -> [CGFloat] {
        (tool == .text ? Self.fontSizes : Self.lineWidths).map { $0 * scaleFactor }
    }

    // MARK: - Actions

    @objc private func undoTapped(_ sender: NSButton) { onEvent?(.undo) }
    @objc private func redoTapped(_ sender: NSButton) { onEvent?(.redo) }

    @objc private func toolTapped(_ sender: NSButton) {
        guard Self.toolSpecs.indices.contains(sender.tag) else { return }
        onEvent?(.selectTool(Self.toolSpecs[sender.tag].tool))
    }

    @objc private func swatchTapped(_ sender: NSButton) {
        guard let swatch = sender as? SwatchButton else { return }
        var style = currentStyle
        style.strokeColor = swatch.color
        onEvent?(.setStyle(style))
    }

    @objc private func widthTapped(_ sender: NSButton) {
        let values = sizeValues(for: currentTool)
        guard values.indices.contains(sender.tag) else { return }
        var style = currentStyle
        if currentTool == .text {
            style.fontSize = values[sender.tag]
        } else {
            style.lineWidth = values[sender.tag]
        }
        onEvent?(.setStyle(style))
    }

    @objc private func blurToggleTapped(_ sender: NSButton) {
        onEvent?(.setBlurMode(currentBlurMode == .gaussian ? .pixelate : .gaussian))
    }

    @objc private func presetChosen(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        onEvent?(.setBackground(index <= 0 ? nil : presets[index - 1]))
    }

    @objc private func copyTapped(_ sender: NSButton) { onCopy?() }
    @objc private func doneTapped(_ sender: NSButton) { onDone?() }
    @objc private func applyTapped(_ sender: NSButton) { onCropApply?() }
    @objc private func cancelTapped(_ sender: NSButton) { onCropCancel?() }
}

/// A 14 pt color dot; a bone ring when it is the current stroke color.
@MainActor
private final class SwatchButton: NSButton {
    let color: BrandColor
    var isCurrent: Bool = false {
        didSet {
            guard isCurrent != oldValue else { return }
            applyRing()
        }
    }

    init(color: BrandColor, target: AnyObject?, action: Selector?) {
        self.color = color
        super.init(frame: .zero)
        self.target = target
        self.action = action
        title = ""
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.backgroundColor = color.cgColor()
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        heightAnchor.constraint(equalToConstant: 14).isActive = true
        applyRing()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func applyRing() {
        layer?.borderWidth = isCurrent ? 2 : 1
        layer?.borderColor = (isCurrent ? BrandPalette.bone : BrandPalette.line).cgColor()
    }
}

/// The 44x28 render thumbnail in the toolbar's corner; dragging it starts an `NSDraggingSession` with a PNG
/// written to a temp file, the same pattern `PreviewContentView` uses for the panel's own thumbnail drag.
@MainActor
private final class DragHandleView: NSImageView, NSDraggingSource {
    /// Supplies the image to export at the moment a drag starts; set by `EditorToolbar.refresh(from:)`.
    var renderProvider: (() -> CGImage?)?
    private var mouseDownPoint: NSPoint?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = BrandPalette.line.cgColor()
        imageScaling = .scaleProportionallyUpOrDown
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard abs(point.x - start.x) > 4 || abs(point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        guard let render = renderProvider?(), let png = ImageCodec.pngData(from: render) else { return }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MiracleShot", isDirectory: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
        } catch {
            return
        }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(png, forType: .png)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
