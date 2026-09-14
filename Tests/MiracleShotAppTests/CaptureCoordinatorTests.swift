import XCTest
import MiracleShotCore
@testable import MiracleShotUI

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private var log: CallLog!
    private var capture: FakeCaptureService!
    private var selection: FakeSelection!
    private var clipboard: FakeClipboard!
    private var files: FakeFiles!
    private var notifications: FakeNotifications!
    private var preview: FakePreview!
    private var historyURL: URL!
    private var settings: Settings!
    private var sut: CaptureCoordinator!

    override func setUp() async throws {
        log = CallLog()
        capture = FakeCaptureService(log: log)
        selection = FakeSelection(log: log)
        clipboard = FakeClipboard(log: log)
        files = FakeFiles(log: log)
        notifications = FakeNotifications(log: log)
        preview = FakePreview(log: log)
        historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        settings = Settings.default
        settings.saveDirectoryPath = "/tmp/miracle-shot-tests/shots"
        settings.namingTemplate = NamingTemplate(pattern: "{app}-{seq}")
        sut = CaptureCoordinator(settings: settings, historyURL: historyURL, capture: capture, selection: selection,
                                 clipboard: clipboard, files: files, notifications: notifications, preview: preview)
    }

    func testAreaCaptureHappyPath() async {
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries, [
            "hasPermission", "present(area)",
            "capture(area(rect: (1.0, 2.0, 30.0, 40.0), displayID: 1))",
            "copy", "save(Safari-1.png, shots)", "preview",
        ])
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.history.entries.count, 1)
        XCTAssertEqual(sut.history.entries.first?.path, "/tmp/miracle-shot-tests/shots/Safari-1.png")
        XCTAssertEqual(preview.lastFileURL?.lastPathComponent, "Safari-1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyURL.path))
    }

    func testFullScreenSkipsSelection() async {
        await sut.perform(.captureFullScreen)
        XCTAssertEqual(log.entries.prefix(2), ["hasPermission", "captureDisplay"])
        XCTAssertEqual(sut.state, .previewing)
    }

    func testCancelledSelectionDoesNothingElse() async {
        selection.result = nil
        await sut.perform(.captureWindow)
        XCTAssertEqual(log.entries, ["hasPermission", "present(window)"])
        XCTAssertEqual(sut.state, .idle)
    }

    func testMissingPermissionRequestsAndNotifies() async {
        capture.permission = false
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries, ["hasPermission", "requestPermission", "notify(error)"])
        XCTAssertEqual(sut.state, .idle)
    }

    func testCaptureFailureNotifiesAndReturnsToIdle() async {
        capture.error = .emptyImage
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries.last, "notify(error)")
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.history.entries.isEmpty)
    }

    func testSaveFallsBackToPicturesFolder() async {
        files.failingDirectories = [settings.saveDirectoryURL.path]
        await sut.perform(.captureArea)
        XCTAssertEqual(log.entries.suffix(4), [
            "save(Safari-1.png, shots)", "save(Safari-1.png, Miracle Shot)", "notify(info)", "preview",
        ])
        XCTAssertEqual(sut.history.entries.first?.path, Settings.fallbackSaveDirectory.appendingPathComponent("Safari-1.png").path)
    }

    func testSaveFailingEverywhereStillCopiesAndPreviews() async {
        files.failAll = true
        await sut.perform(.captureArea)
        XCTAssertTrue(log.entries.contains("copy"))
        XCTAssertEqual(log.entries.last, "preview")
        XCTAssertEqual(notifications.posted.last?.isError, true)
        XCTAssertNil(preview.lastFileURL)
        XCTAssertTrue(sut.history.entries.isEmpty)
    }

    func testSecondHotkeyWhileSelectingIsIgnored() async {
        selection.hold = true
        let task = Task { await sut.perform(.captureArea) }
        while selection.presentCount == 0 { await Task.yield() }
        await sut.perform(.captureWindow)
        XCTAssertEqual(selection.presentCount, 1)
        XCTAssertEqual(sut.state, .selecting(.area))
        selection.resume()
        await task.value
        XCTAssertEqual(sut.state, .previewing)
    }

    func testPreviewDismissReturnsToIdleAndHotkeyWhilePreviewingRestarts() async {
        await sut.perform(.captureArea)
        preview.onDismiss?()
        XCTAssertEqual(sut.state, .idle)
        await sut.perform(.captureArea)
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.history.entries.map(\.path).first, "/tmp/miracle-shot-tests/shots/Safari-2.png")
    }

    func testStateChangeCallbackFires() async {
        var seen: [CaptureState] = []
        sut.onStateChange = { seen.append($0) }
        await sut.perform(.captureArea)
        XCTAssertEqual(seen, [.selecting(.area), .capturing, .previewing])
    }

    func testStaleDismissFromReplacedPreviewIsIgnored() async {
        await sut.perform(.captureArea)
        let stale = preview.onDismiss
        await sut.perform(.captureArea)          // allowed while previewing; replaces the preview
        XCTAssertEqual(sut.state, .previewing)
        stale?()
        XCTAssertEqual(sut.state, .previewing, "a superseded preview must not reset the new flow")
        preview.onDismiss?()
        XCTAssertEqual(sut.state, .idle)
    }

    func testRemoveFromHistoryPersistsAndNotifies() async throws {
        await sut.perform(.captureArea)
        var notified: [Int] = []
        sut.onHistoryChange = { notified.append($0.entries.count) }
        let id = try XCTUnwrap(sut.history.entries.first?.id)
        sut.removeFromHistory(id: id)
        XCTAssertTrue(sut.history.entries.isEmpty)
        XCTAssertEqual(notified, [0])
        XCTAssertTrue(HistoryIndex.load(from: historyURL, limit: 50).entries.isEmpty)
    }

    func testWindowCaptureCarriesWindowInfo() async {
        let window = WindowInfo(id: 7, frame: CGRect(x: 0, y: 0, width: 100, height: 50), layer: 0,
                                ownerName: "Safari", ownerPID: 1, title: "Apple")
        selection.result = .window(window)
        await sut.perform(.captureWindow)
        XCTAssertTrue(log.entries.contains { $0.hasPrefix("capture(window(") })
        XCTAssertEqual(sut.state, .previewing)
    }

    func testErrorToastUsesReadableDescription() async {
        capture.error = .permissionDenied
        await sut.perform(.captureArea)
        XCTAssertEqual(notifications.posted.last?.title, "Capture failed")
        XCTAssertEqual(notifications.lastBody, "Screen Recording permission is not granted.")
    }

    func testClearHistoryPersistsOnceAndNotifiesOnce() async {
        await sut.perform(.captureArea)
        preview.onDismiss?()
        await sut.perform(.captureArea)
        var notifications = 0
        sut.onHistoryChange = { _ in notifications += 1 }
        sut.clearHistory()
        XCTAssertTrue(sut.history.entries.isEmpty)
        XCTAssertEqual(notifications, 1)
        XCTAssertTrue(HistoryIndex.load(from: historyURL, limit: 50).entries.isEmpty)
    }

    private var solidPreset: BackgroundPreset {
        BackgroundPreset(id: "t", name: "T", fill: .solid(color: BrandPalette.lime), padding: 10, cornerRadius: 0, shadow: nil)
    }

    func testApplyBackgroundRunsTheFinishPathAgain() async {
        await sut.perform(.captureArea)
        let source = sut.lastCapture!
        log.entries.removeAll()

        sut.applyBackground(solidPreset, to: source)

        XCTAssertEqual(log.entries.first, "copy")
        XCTAssertTrue(log.entries[1].hasPrefix("save("))
        XCTAssertEqual(log.entries.last, "preview")
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(files.lastSaved?.pixelWidth, source.pixelWidth + 20)
        XCTAssertEqual(files.lastSaved?.pixelHeight, source.pixelHeight + 20)
        XCTAssertEqual(sut.history.entries.count, 2)
        XCTAssertEqual(sut.history.entries.first?.sourceApp, "Safari")
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.lastCapture?.pixelWidth, source.pixelWidth + 20)
    }

    func testApplyBackgroundIsIgnoredWhileSelecting() async {
        selection.hold = true
        let task = Task { await sut.perform(.captureArea) }
        await Task.yield()
        XCTAssertEqual(sut.state, .selecting(.area))
        sut.applyBackground(solidPreset, to: makeCapture())
        XCTAssertFalse(log.entries.contains("copy"))
        selection.result = nil
        selection.resume()
        await task.value
    }

    /// Hotkey during the preview, then Esc: the panel is still on screen while the state is idle again.
    func testApplyBackgroundWorksAfterCancelledCaptureLeftThePanelUp() async {
        await sut.perform(.captureArea)
        selection.result = nil
        await sut.perform(.captureArea)
        XCTAssertEqual(sut.state, .idle)
        log.entries.removeAll()
        sut.applyBackground(solidPreset, to: makeCapture())
        XCTAssertEqual(log.entries.first, "copy")
        XCTAssertEqual(log.entries.last, "preview")
    }

    func testApplyBackgroundScalesPaddingByCaptureScale() async {
        await sut.perform(.captureArea)
        let source = Capture(image: makeTestImage(width: 8, height: 6), bounds: CGRect(x: 0, y: 0, width: 4, height: 3), scaleFactor: 2)
        sut.applyBackground(solidPreset, to: source)
        XCTAssertEqual(files.lastSaved?.pixelWidth, 8 + 40)
        XCTAssertEqual(files.lastSaved?.bounds.size, CGSize(width: 24, height: 23))
    }

    func testDismissOfSupersededPreviewDoesNotResetAfterApplyBackground() async {
        await sut.perform(.captureArea)
        let firstDismiss = preview.onDismiss
        sut.applyBackground(solidPreset, to: sut.lastCapture!)
        firstDismiss?()
        XCTAssertEqual(sut.state, .previewing)
        preview.onDismiss?()
        XCTAssertEqual(sut.state, .idle)
    }
}
