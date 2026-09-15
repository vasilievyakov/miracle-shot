import AppKit
import MiracleShotCore

/// Opens screenshots as floating always-on-top pin panels, positioned exactly where they were captured.
@MainActor
public final class PinController {
    private static let fadeInDuration: TimeInterval = 0.18

    private var panels: [PinPanel] = []

    public init() {}

    /// Pins `capture` in place: a new panel opens at the capture's original screen location, at scale 1, and
    /// fades in. The panel is kept alive until it closes itself (Esc, double-click) and calls `onClose`.
    public func pin(_ capture: Capture) {
        let frame = SelectionGeometry.flipped(capture.bounds, primaryScreenHeight: NSScreen.primaryHeight)
        let panel = PinPanel(image: capture.image, frame: frame)
        panel.onClose = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panels.removeAll { $0 === panel }
        }
        panels.append(panel)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeInDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = panel.transform.opacity
        }
    }
}
