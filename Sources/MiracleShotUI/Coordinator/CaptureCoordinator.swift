import Foundation
import MiracleShotCore

/// Owns the capture state machine and drives the services. All side effects go through protocols so
/// every path here is covered by `CaptureCoordinatorTests` with fakes.
@MainActor
public final class CaptureCoordinator {
    public private(set) var state: CaptureState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public private(set) var history: HistoryIndex
    public private(set) var lastCapture: Capture?
    public var settings: Settings
    public var onStateChange: ((CaptureState) -> Void)?
    public var onHistoryChange: ((HistoryIndex) -> Void)?

    private let historyURL: URL
    private let capture: CaptureServicing
    private let selection: SelectionPresenting
    private let clipboard: ClipboardServicing
    private let files: FileSaving
    private let notifications: NotificationPosting
    private let preview: PreviewPresenting
    private var sequence = 0

    public init(settings: Settings, historyURL: URL, capture: CaptureServicing, selection: SelectionPresenting,
                clipboard: ClipboardServicing, files: FileSaving, notifications: NotificationPosting,
                preview: PreviewPresenting) {
        self.settings = settings
        self.historyURL = historyURL
        self.history = HistoryIndex.load(from: historyURL, limit: settings.historyLimit)
        self.capture = capture
        self.selection = selection
        self.clipboard = clipboard
        self.files = files
        self.notifications = notifications
        self.preview = preview
    }

    public func perform(_ action: CaptureAction) async {
        guard state.canStartCapture else { return }
        guard capture.hasPermission() else {
            capture.requestPermission()
            notifications.post(title: "Screen Recording permission needed",
                               body: "Allow Miracle Shot in System Settings > Privacy & Security > Screen Recording.",
                               isError: true)
            return
        }

        let mode = action.captureMode
        transition(.hotkey(mode))

        var selected: SelectionResult?
        if mode != .fullScreen {
            guard let result = await selection.present(mode: mode) else {
                transition(.selectionCancelled)
                return
            }
            transition(.selectionMade)
            selected = result
        }

        do {
            let shot: Capture
            if let selected {
                shot = try await capture.capture(selected)
            } else {
                shot = try await capture.captureDisplayUnderCursor()
            }
            transition(.captureSucceeded)
            finish(shot)
        } catch {
            transition(.captureFailed)
            notifications.post(title: "Capture failed", body: String(describing: error), isError: true)
        }
    }

    public func removeFromHistory(id: UUID) {
        history.remove(id: id)
        persistHistory()
    }

    // MARK: - Private

    private func transition(_ event: CaptureEvent) {
        state = CaptureStateMachine.reduce(state, event)
    }

    private func finish(_ shot: Capture) {
        lastCapture = shot
        clipboard.copy(shot)
        let fileURL = saveToDisk(shot)
        if let fileURL {
            history.append(HistoryEntry(path: fileURL.path, date: shot.timestamp, width: shot.pixelWidth,
                                        height: shot.pixelHeight, sourceApp: shot.sourceAppName))
            persistHistory()
        }
        preview.show(capture: shot, fileURL: fileURL) { [weak self] in
            self?.transition(.previewDismissed)
        }
    }

    private func saveToDisk(_ shot: Capture) -> URL? {
        sequence += 1
        let name = settings.namingTemplate.fileName(date: shot.timestamp, appName: shot.sourceAppName, sequence: sequence)
        do {
            return try files.save(shot, named: name, in: settings.saveDirectoryURL)
        } catch {
            do {
                let url = try files.save(shot, named: name, in: Settings.fallbackSaveDirectory)
                notifications.post(title: "Saved to Pictures/Miracle Shot",
                                   body: "The configured folder is not writable.", isError: false)
                return url
            } catch {
                notifications.post(title: "Could not save screenshot", body: String(describing: error), isError: true)
                return nil
            }
        }
    }

    private func persistHistory() {
        try? history.save(to: historyURL)
        onHistoryChange?(history)
    }
}
