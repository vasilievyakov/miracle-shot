import AppKit
import MiracleShotCore

/// Shows one transparent panel per screen and resolves the `present` continuation exactly once.
@MainActor
public final class SelectionOverlayController: SelectionPresenting {
    private let capture: CaptureServicing
    private let windowList: WindowListProviding
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<SelectionResult?, Never>?

    public init(capture: CaptureServicing, windowList: WindowListProviding) {
        self.capture = capture
        self.windowList = windowList
    }

    public func present(mode: CaptureMode) async -> SelectionResult? {
        guard continuation == nil else { return nil }
        let windows = windowList.onScreenWindows()
        var frozen: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            if let shot = try? await capture.captureDisplay(screen.displayID) { frozen[screen.displayID] = shot.image }
        }
        panels = NSScreen.screens.map {
            SelectionPanel(screen: $0, mode: mode, controller: self, windows: windows, frozen: frozen[$0.displayID])
        }
        for panel in panels { panel.orderFrontRegardless() }
        panels.first?.makeKey()
        NSCursor.crosshair.push()
        return await withCheckedContinuation { continuation = $0 }
    }

    /// Called when a panel resigns key. If no overlay panel is key on the next run loop turn, focus went elsewhere
    /// (app switch, Space change) and the selection is cancelled so the continuation and cursor are not leaked.
    func keyStatusChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.continuation != nil else { return }
            if !self.panels.contains(where: { $0.isKeyWindow }) {
                self.finish(with: nil)
            }
        }
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
