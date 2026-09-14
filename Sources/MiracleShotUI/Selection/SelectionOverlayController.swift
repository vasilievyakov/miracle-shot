import AppKit
import MiracleShotCore

/// Shows one transparent panel per screen and resolves the `present` continuation exactly once.
@MainActor
public final class SelectionOverlayController: SelectionPresenting {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult?, Never>?

    public init() {}

    public func present(mode: CaptureMode) async -> SelectionResult? {
        guard continuation == nil else { return nil }
        panels = NSScreen.screens.map { SelectionPanel(screen: $0, mode: mode, controller: self) }
        for panel in panels { panel.orderFrontRegardless() }
        panels.first?.makeKey()
        NSCursor.crosshair.push()
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with result: SelectionResult?) {
        guard let continuation else { return }
        self.continuation = nil
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        continuation.resume(returning: result)
    }
}
