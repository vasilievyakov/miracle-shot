import AppKit
import MiracleShotCore

/// A floating always-on-top panel showing a pinned screenshot at the place it was taken. Movable by its
/// background, closed by Esc or a double-click, with keyboard/wheel opacity and scale and a short HUD readout.
@MainActor
public final class PinPanel: NSPanel {
    private static let hudInset: CGFloat = 8
    private static let hudPaddingX: CGFloat = 10
    private static let hudPaddingY: CGFloat = 5
    private static let hudVisibleDuration: TimeInterval = 0.6
    private static let fadeOutDuration: TimeInterval = 0.12

    /// Natural (scale 1) size in points; the frame is always this times `transform.scale`.
    private let naturalSize: NSSize
    private let content: NSView
    private let imageView: NSImageView
    private let hudContainer: NSView
    private let hudLabel: NSTextField
    private var hudWorkItem: DispatchWorkItem?

    /// Called once after the panel has faded out and ordered off screen.
    public var onClose: (() -> Void)?

    public var transform = PinTransform() {
        didSet { applyTransform(previous: oldValue) }
    }

    /// `frame` is the AppKit frame (already flipped from CG global coordinates) the panel opens at, at scale 1.
    public init(image: CGImage, frame: CGRect) {
        naturalSize = frame.size

        imageView = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
        imageView.image = NSImage(cgImage: image, size: frame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]

        hudLabel = NSTextField(labelWithString: "")
        hudLabel.font = BrandFont.mono(size: 12, weight: 600)
        hudLabel.textColor = BrandPalette.bone.nsColor()
        hudLabel.alignment = .center

        hudContainer = NSView()
        hudContainer.wantsLayer = true
        hudContainer.layer?.backgroundColor = BrandPalette.ink2.cgColor()
        hudContainer.layer?.cornerRadius = 6
        hudContainer.layer?.borderWidth = 1
        hudContainer.layer?.borderColor = BrandPalette.line.cgColor()
        hudContainer.isHidden = true
        hudContainer.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]
        hudContainer.addSubview(hudLabel)

        content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.addSubview(imageView)
        content.addSubview(hudContainer)

        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        contentView = content

        layoutHUD()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override public var canBecomeKey: Bool { true }

    // MARK: - Events

    override public func mouseDown(with event: NSEvent) {
        makeKey()
        if event.clickCount == 2 {
            requestClose()
        } else {
            super.mouseDown(with: event)
        }
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {   // Escape
            requestClose()
            return
        }
        switch event.charactersIgnoringModifiers {
        case "+", "=":
            transform = transform.scaledUp()
            showHUD(transform.scaleLabel)
        case "-":
            transform = transform.scaledDown()
            showHUD(transform.scaleLabel)
        case "]":
            transform = transform.opacityIncreased()
            showHUD(transform.opacityLabel)
        case "[":
            transform = transform.opacityDecreased()
            showHUD(transform.opacityLabel)
        case "0":
            transform = .identity
            showHUD(transform.scaleLabel)
        default:
            super.keyDown(with: event)
        }
    }

    override public func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
            guard delta != 0 else { return }
            transform = delta > 0 ? transform.opacityIncreased() : transform.opacityDecreased()
            showHUD(transform.opacityLabel)
            return
        }
        let lines = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.deltaY
        guard lines != 0 else { return }
        transform = transform.wheeled(lines: lines)
        showHUD(transform.scaleLabel)
    }

    // MARK: - Transform

    /// Applies opacity immediately; on a scale change resizes the frame to `naturalSize * scale` around the
    /// panel's current center so zooming never drifts the pin off the point it was pinned at.
    private func applyTransform(previous: PinTransform) {
        alphaValue = transform.opacity
        guard transform.scale != previous.scale else { return }
        let newSize = NSSize(width: naturalSize.width * transform.scale, height: naturalSize.height * transform.scale)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let origin = NSPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        setFrame(NSRect(origin: origin, size: newSize), display: true, animate: false)
    }

    // MARK: - HUD

    /// Shows `text` in the HUD, resetting the 600 ms auto-hide timer.
    private func showHUD(_ text: String) {
        hudLabel.stringValue = text
        hudLabel.sizeToFit()
        layoutHUD()
        hudContainer.isHidden = false
        hudWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.hudContainer.isHidden = true }
        hudWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudVisibleDuration, execute: workItem)
    }

    private func layoutHUD() {
        let labelSize = hudLabel.frame.size
        let size = NSSize(width: labelSize.width + Self.hudPaddingX * 2, height: labelSize.height + Self.hudPaddingY * 2)
        hudLabel.frame = NSRect(x: Self.hudPaddingX, y: Self.hudPaddingY, width: labelSize.width, height: labelSize.height)
        let origin = NSPoint(x: (content.bounds.width - size.width) / 2, y: Self.hudInset)
        hudContainer.frame = NSRect(origin: origin, size: size)
    }

    // MARK: - Closing

    private var isClosing = false

    private func requestClose() {
        guard !isClosing else { return }
        isClosing = true
        hudWorkItem?.cancel()
        hudWorkItem = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOutDuration
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.orderOut(nil)
                self.onClose?()
            }
        })
    }
}
