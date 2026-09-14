import AppKit
import MiracleShotCore

/// Thumbnail plus action buttons. Reports hover to the owner and starts a file drag from the thumbnail.
@MainActor
final class PreviewContentView: NSView, NSDraggingSource {
    static let maxThumbnail = NSSize(width: 240, height: 150)

    var onHover: ((Bool) -> Void)?
    var onPrimaryAction: (() -> Void)?

    private let capture: Capture
    private let fileURL: URL?
    private let thumbnail = NSImageView()
    private var tracking: NSTrackingArea?
    private var mouseDownPoint: NSPoint?

    init(capture: Capture, fileURL: URL?, buttons: [BrandButton]) {
        self.capture = capture
        self.fileURL = fileURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = BrandPalette.ink2.cgColor()
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = BrandPalette.line.cgColor()

        let image = NSImage(cgImage: capture.image, size: capture.bounds.size)
        thumbnail.image = image
        thumbnail.imageScaling = .scaleProportionallyDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 6
        thumbnail.layer?.masksToBounds = true
        let fit = Self.fit(capture.bounds.size, into: Self.maxThumbnail)
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.widthAnchor.constraint(equalToConstant: fit.width).isActive = true
        thumbnail.heightAnchor.constraint(equalToConstant: fit.height).isActive = true

        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 6

        let stack = NSStackView(views: buttons.isEmpty ? [thumbnail] : [thumbnail, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func fit(_ size: CGSize, into box: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 60, height: 60) }
        let ratio = min(box.width / size.width, box.height / size.height, 1)
        return NSSize(width: max(60, (size.width * ratio).rounded()), height: max(40, (size.height * ratio).rounded()))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    // MARK: Click and drag on the thumbnail

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = thumbnail.frame.contains(point) ? point : nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard abs(point.x - start.x) > 4 || abs(point.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let item = NSPasteboardItem()
        if let fileURL {
            item.setString(fileURL.absoluteString, forType: .fileURL)
        } else if let png = ImageCodec.pngData(from: capture.image) {
            item.setData(png, forType: .png)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(thumbnail.convert(thumbnail.bounds, to: self), contents: thumbnail.image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownPoint != nil { onPrimaryAction?() }
        mouseDownPoint = nil
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
