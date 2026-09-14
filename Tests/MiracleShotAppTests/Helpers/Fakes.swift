import CoreGraphics
import Foundation
import MiracleShotCore
@testable import MiracleShotUI

/// Shared call log so tests can assert the order of side effects.
@MainActor final class CallLog {
    var entries: [String] = []
    func add(_ s: String) { entries.append(s) }
}

func makeTestImage(width: Int = 8, height: Int = 6) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [0.2, 0.4, 0.6, 1])!)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

func makeCapture() -> Capture {
    Capture(image: makeTestImage(), timestamp: Date(timeIntervalSince1970: 1_789_394_709),
            sourceAppName: "Safari", sourceWindowTitle: nil,
            bounds: CGRect(x: 0, y: 0, width: 8, height: 6), scaleFactor: 1)
}

@MainActor final class FakeCaptureService: CaptureServicing {
    let log: CallLog
    var permission = true
    var error: CaptureError?
    init(log: CallLog) { self.log = log }

    func hasPermission() -> Bool { log.add("hasPermission"); return permission }
    func requestPermission() { log.add("requestPermission") }
    func capture(_ selection: SelectionResult) async throws -> Capture {
        log.add("capture(\(selection))")
        if let error { throw error }
        return makeCapture()
    }
    func captureDisplayUnderCursor() async throws -> Capture {
        log.add("captureDisplay")
        if let error { throw error }
        return makeCapture()
    }
}

@MainActor final class FakeSelection: SelectionPresenting {
    let log: CallLog
    var result: SelectionResult? = .area(rect: CGRect(x: 1, y: 2, width: 30, height: 40), displayID: 1)
    var hold = false
    private(set) var presentCount = 0
    private var continuation: CheckedContinuation<SelectionResult?, Never>?
    init(log: CallLog) { self.log = log }

    func present(mode: CaptureMode) async -> SelectionResult? {
        presentCount += 1
        log.add("present(\(mode))")
        guard hold else { return result }
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor final class FakeClipboard: ClipboardServicing {
    let log: CallLog
    init(log: CallLog) { self.log = log }
    func copy(_ capture: Capture) { log.add("copy") }
}

@MainActor final class FakeFiles: FileSaving {
    let log: CallLog
    /// Directories whose saves throw.
    var failingDirectories: Set<String> = []
    var failAll = false
    init(log: CallLog) { self.log = log }
    struct SaveError: Error {}

    func save(_ capture: Capture, named fileName: String, in directory: URL) throws -> URL {
        log.add("save(\(fileName), \(directory.lastPathComponent))")
        if failAll || failingDirectories.contains(directory.path) { throw SaveError() }
        return directory.appendingPathComponent(fileName)
    }
}

@MainActor final class FakeNotifications: NotificationPosting {
    let log: CallLog
    var posted: [(title: String, isError: Bool)] = []
    init(log: CallLog) { self.log = log }
    func post(title: String, body: String, isError: Bool) {
        log.add("notify(\(isError ? "error" : "info"))")
        posted.append((title, isError))
    }
}

@MainActor final class FakePreview: PreviewPresenting {
    let log: CallLog
    var lastFileURL: URL?
    var onDismiss: (@MainActor () -> Void)?
    init(log: CallLog) { self.log = log }
    func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void) {
        log.add("preview")
        lastFileURL = fileURL
        self.onDismiss = onDismiss
    }
}
