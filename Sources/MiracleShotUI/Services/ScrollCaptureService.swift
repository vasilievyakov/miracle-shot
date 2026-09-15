import ApplicationServices
import CoreGraphics
import Foundation
import MiracleShotCore
import os

/// Drives a scrolling capture: repeatedly grabs the window, either by scrolling it itself (when Accessibility is
/// granted) or by watching the user scroll it by hand, then stitches the frames with `ImageStitcher`.
@MainActor
public final class ScrollCaptureService: ScrollCapturing {
    private let capture: CaptureServicing
    private let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "scroll")

    private static let maxKeptFrames = 50
    private static let maxDuration: TimeInterval = 30
    /// Auto mode: how long to wait, at most, for a scroll animation to settle before giving up and using
    /// whatever was last captured.
    private static let settleTimeout: TimeInterval = 0.4
    private static let settleStep: Duration = .milliseconds(80)
    private static let manualPollInterval: Duration = .milliseconds(150)

    public init(capture: CaptureServicing) {
        self.capture = capture
    }

    public func captureScrolling(window info: WindowInfo) async throws -> ScrollCaptureResult {
        let frame0 = try await capture.capture(.window(info))
        var frames: [CGImage] = [frame0.image]

        let hud = ScrollHUDPanel(anchorWindow: info)
        defer { hud.orderOut(nil) }
        var escapePressed = false
        var returnPressed = false
        hud.onEscape = { escapePressed = true }
        hud.onReturn = { returnPressed = true }

        let started = Date()
        let deadline = started.addingTimeInterval(Self.maxDuration)
        let auto = AXIsProcessTrusted()

        if auto {
            hud.text = "Scrolling... \(frames.count) frames. Esc to stop"
            hud.show()
            let center = CGPoint(x: info.frame.midX, y: info.frame.midY)
            CGWarpMouseCursorPosition(center)
            let step = Int(info.frame.height * 0.75)

            while frames.count < Self.maxKeptFrames, Date() < deadline, !escapePressed {
                postScroll(step: step, at: center)
                let settled = try await waitForSettledFrame(info: info)
                let lastKept = frames[frames.count - 1]
                guard FrameDiff.difference(lastKept, settled) >= FrameDiff.samePageThreshold else { break }
                frames.append(settled)
                hud.text = "Scrolling... \(frames.count) frames. Esc to stop"
            }
        } else {
            hud.text = "Scroll the window with the mouse or trackpad, then press Return. Esc cancels."
            hud.show()
            var previousPoll: CGImage?

            while frames.count < Self.maxKeptFrames, Date() < deadline, !returnPressed, !escapePressed {
                try await Task.sleep(for: Self.manualPollInterval)
                guard !returnPressed, !escapePressed else { break }
                let polled = try await capture.capture(.window(info)).image
                if let previousPoll, FrameDiff.difference(previousPoll, polled) < FrameDiff.settledThreshold {
                    let lastKept = frames[frames.count - 1]
                    if FrameDiff.difference(lastKept, polled) >= FrameDiff.samePageThreshold {
                        frames.append(polled)
                    }
                }
                previousPoll = polled
            }
        }

        if !auto, escapePressed {
            throw CaptureError.cancelled
        }

        guard let stitched = ImageStitcher.stitch(frames) else { throw CaptureError.noFrames }

        let elapsed = Date().timeIntervalSince(started)
        log.info("""
            Scrolling capture: mode=\(auto ? "auto" : "manual", privacy: .public) \
            frames=\(frames.count, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2), privacy: .public)s \
            fallback=\(stitched.usedFallback, privacy: .public)
            """)
        dumpFramesIfRequested(frames: frames, stitched: stitched.image)

        let bounds = CGRect(origin: info.frame.origin,
                            size: CGSize(width: info.frame.width, height: CGFloat(stitched.image.height) / frame0.scaleFactor))
        let shot = Capture(image: stitched.image, sourceAppName: info.ownerName, sourceWindowTitle: info.title,
                           bounds: bounds, scaleFactor: frame0.scaleFactor)
        return ScrollCaptureResult(capture: shot, usedFallback: stitched.usedFallback)
    }

    // MARK: - Auto mode

    private func postScroll(step: Int, at location: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: Int32(-step), wheel2: 0, wheel3: 0) else { return }
        event.location = location
        event.post(tap: .cghidEventTap)
    }

    /// Sleeps in `settleStep` increments, capturing and comparing to the previous poll each time, until the
    /// image stops changing (below `FrameDiff.settledThreshold`) or `settleTimeout` has elapsed, whichever
    /// comes first; either way the last captured frame is returned.
    private func waitForSettledFrame(info: WindowInfo) async throws -> CGImage {
        var previousPoll: CGImage?
        var waited: TimeInterval = 0
        while true {
            try await Task.sleep(for: Self.settleStep)
            waited += 0.08
            let polled = try await capture.capture(.window(info)).image
            if let previousPoll, FrameDiff.difference(previousPoll, polled) < FrameDiff.settledThreshold {
                return polled
            }
            if waited >= Self.settleTimeout {
                return polled
            }
            previousPoll = polled
        }
    }

    // MARK: - Debug dump

    /// Writes every kept frame and the stitched result as PNGs under `MIRACLE_SHOT_SCROLL_DUMP`, when set.
    private func dumpFramesIfRequested(frames: [CGImage], stitched: CGImage) {
        guard let path = ProcessInfo.processInfo.environment["MIRACLE_SHOT_SCROLL_DUMP"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (index, frame) in frames.enumerated() {
                guard let data = ImageCodec.pngData(from: frame) else { continue }
                try data.write(to: directory.appendingPathComponent(String(format: "frame-%02d.png", index)))
            }
            if let data = ImageCodec.pngData(from: stitched) {
                try data.write(to: directory.appendingPathComponent("stitched.png"))
            }
        } catch {
            log.error("Could not write scroll dump to \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
