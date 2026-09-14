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

    private var freezeTasks: [Task<Void, Never>] = []

    /// The dim appears immediately; frozen screen images arrive asynchronously per display and are painted in
    /// as they land, so the hotkey never waits for a full-screen capture.
    public func present(mode: CaptureMode) async -> SelectionResult? {
        guard continuation == nil else { return nil }
        let windows = windowList.onScreenWindows()
        panels = NSScreen.screens.map {
            SelectionPanel(screen: $0, mode: mode, controller: self, windows: windows, frozen: nil)
        }
        for panel in panels { panel.orderFrontRegardless() }
        panels.first?.makeKey()
        NSCursor.crosshair.push()
        freezeScreens()
        return await withCheckedContinuation { continuation = $0 }
    }

    /// One main-actor task per display; they suspend inside ScreenCaptureKit and so run concurrently.
    private func freezeScreens() {
        freezeTasks.forEach { $0.cancel() }
        freezeTasks = NSScreen.screens.map { screen in
            let id = screen.displayID
            return Task { [weak self] in
                guard let self, let shot = try? await self.capture.captureDisplay(id) else { return }
                guard !Task.isCancelled, self.continuation != nil else { return }
                self.panels.first { $0.displayID == id }?.setFrozen(shot.image)
            }
        }
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
        freezeTasks.forEach { $0.cancel() }
        freezeTasks.removeAll()
        NSCursor.pop()
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        continuation.resume(returning: result)
    }
}
