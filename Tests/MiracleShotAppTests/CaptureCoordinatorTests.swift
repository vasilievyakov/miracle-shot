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
    private var ocr: FakeOCR!
    private var scroll: FakeScrollCapture!
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
        ocr = FakeOCR(log: log)
        scroll = FakeScrollCapture(log: log)
        historyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        settings = Settings.default
        settings.saveDirectoryPath = "/tmp/miracle-shot-tests/shots"
        settings.namingTemplate = NamingTemplate(pattern: "{app}-{seq}")
        sut = CaptureCoordinator(settings: settings, historyURL: historyURL, capture: capture, selection: selection,
                                 clipboard: clipboard, files: files, notifications: notifications, preview: preview,
                                 ocr: ocr, scroll: scroll)
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
        BackgroundPreset(id: "t", name: "T", fill: .solid(color: BrandPalette.lime), paddingPercent: 10, cornerRadiusPercent: 0, shadow: nil)
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
        // The 8x6 test capture: reference (8+6)/2=7, paddingPercent 10 -> 0.7 px, under the 24 pt floor -> padding
        // 24 px on every side -> +48 total.
        XCTAssertEqual(files.lastSaved?.pixelWidth, source.pixelWidth + 48)
        XCTAssertEqual(files.lastSaved?.pixelHeight, source.pixelHeight + 48)
        XCTAssertEqual(sut.history.entries.count, 2)
        XCTAssertEqual(sut.history.entries.first?.sourceApp, "Safari")
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(sut.lastCapture?.pixelWidth, source.pixelWidth + 48)
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
        // reference (8+6)/2=7, paddingPercent 10 -> 0.7 px, under the 24 pt floor -> floor scaled by 2 -> 48 px on
        // every side -> +96 px total width; in points that is +48 on the 4x3 bounds -> (52, 51).
        XCTAssertEqual(files.lastSaved?.pixelWidth, 8 + 96)
        XCTAssertEqual(files.lastSaved?.bounds.size, CGSize(width: 4 + 48, height: 3 + 48))
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

    func testPublishRunsTheFinishPath() async {
        await sut.perform(.captureArea)
        let source = sut.lastCapture!
        log.entries.removeAll()

        let image = makeTestImage(width: 20, height: 10)
        sut.publish(image, derivedFrom: source)

        XCTAssertEqual(log.entries.first, "copy")
        XCTAssertTrue(log.entries[1].hasPrefix("save("))
        XCTAssertEqual(log.entries.last, "preview")
        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(sut.history.entries.count, 2)
        XCTAssertEqual(sut.lastCapture?.pixelWidth, image.width)
        XCTAssertEqual(sut.lastCapture?.pixelHeight, image.height)
    }

    func testPublishIsRefusedWhileSelecting() async {
        selection.hold = true
        let task = Task { await sut.perform(.captureArea) }
        await Task.yield()
        XCTAssertEqual(sut.state, .selecting(.area))
        sut.publish(makeTestImage(), derivedFrom: makeCapture())
        XCTAssertFalse(log.entries.contains("copy"))
        selection.result = nil
        selection.resume()
        await task.value
    }

    private struct OCRTestError: LocalizedError {
        var errorDescription: String? { "OCR blew up" }
    }

    func testRecognizeTextCopiesAndNotifies() async {
        let block = TextBlock(text: "Hello world", rect: CGRect(x: 0, y: 0, width: 10, height: 5), confidence: 1)
        ocr.result = OCRResult(blocks: [block])
        await sut.recognizeText(in: makeCapture())
        XCTAssertEqual(log.entries, ["ocr", "copyText", "notify(info)"])
        XCTAssertEqual(clipboard.copiedText, ocr.result.text)
        XCTAssertEqual(notifications.posted.last?.title, "Text copied")
        XCTAssertEqual(notifications.lastBody, ocr.result.preview(lines: 3))
    }

    func testRecognizeTextWithoutTextNotifiesAndLeavesClipboard() async {
        await sut.recognizeText(in: makeCapture())
        XCTAssertFalse(log.entries.contains("copyText"))
        XCTAssertNil(clipboard.copiedText)
        XCTAssertEqual(notifications.posted.last?.title, "No text found")
        XCTAssertEqual(notifications.posted.last?.isError, false)
    }

    func testRecognizeTextFailureNotifiesError() async {
        ocr.error = OCRTestError()
        await sut.recognizeText(in: makeCapture())
        XCTAssertFalse(log.entries.contains("copyText"))
        XCTAssertEqual(notifications.posted.last?.title, "Text recognition failed")
        XCTAssertEqual(notifications.lastBody, "OCR blew up")
        XCTAssertEqual(notifications.posted.last?.isError, true)
    }

    // MARK: - Scrolling capture

    func testCaptureScrollingUsesTheWindowResult() async {
        let window = WindowInfo(id: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 50), layer: 0,
                                ownerName: "Safari", ownerPID: 1, title: "Apple")
        selection.result = .window(window)
        await sut.perform(.captureScrolling)
        XCTAssertEqual(log.entries, [
            "hasPermission", "present(window)", "scroll(9)", "copy", "save(Safari-1.png, shots)", "preview",
        ])
        XCTAssertEqual(sut.state, .previewing)
    }

    func testCaptureScrollingWithAreaResultCancels() async {
        selection.result = .area(rect: CGRect(x: 1, y: 2, width: 30, height: 40), displayID: 1)
        await sut.perform(.captureScrolling)
        XCTAssertFalse(log.entries.contains { $0.hasPrefix("scroll(") })
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(notifications.posted.count, 1)
        XCTAssertEqual(notifications.posted.first?.isError, false)
    }

    func testCaptureScrollingCancelledReturnsToIdleQuietly() async {
        let window = WindowInfo(id: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 50), layer: 0,
                                ownerName: "Safari", ownerPID: 1, title: "Apple")
        selection.result = .window(window)
        scroll.error = CaptureError.cancelled
        await sut.perform(.captureScrolling)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(notifications.posted.isEmpty)
    }

    func testCaptureScrollingFailureNotifies() async {
        let window = WindowInfo(id: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 50), layer: 0,
                                ownerName: "Safari", ownerPID: 1, title: "Apple")
        selection.result = .window(window)
        scroll.error = CaptureError.noFrames
        await sut.perform(.captureScrolling)
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(notifications.posted.count, 1)
        XCTAssertEqual(notifications.posted.first?.isError, true)
        XCTAssertEqual(notifications.posted.first?.title, "Capture failed")
    }

    func testCaptureScrollingFallbackNotifies() async {
        let window = WindowInfo(id: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 50), layer: 0,
                                ownerName: "Safari", ownerPID: 1, title: "Apple")
        selection.result = .window(window)
        scroll.result = ScrollCaptureResult(capture: makeCapture(), usedFallback: true)
        await sut.perform(.captureScrolling)
        XCTAssertEqual(sut.state, .previewing)
        XCTAssertEqual(notifications.posted.last?.title, "Some parts could not be aligned and were appended")
        XCTAssertEqual(notifications.posted.last?.isError, false)
    }
}
