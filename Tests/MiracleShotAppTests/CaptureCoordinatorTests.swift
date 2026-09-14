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
}
