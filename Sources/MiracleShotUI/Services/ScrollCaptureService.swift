import AppKit
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
    private let windowList: WindowListProviding
    private let notifications: NotificationPosting
    private let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "scroll")
    /// The Accessibility prompt is shown at most once per launch; later captures fall back to manual mode quietly.
    private var promptedForAccessibility = false

    private static let maxKeptFrames = 50
    private static let maxDuration: TimeInterval = 30
    /// Auto mode: how long to wait, at most, for the scroll and any reveal animation of the newly visible
    /// content to settle before giving up and using whatever was last captured. Static pages settle on the
    /// second poll; the timeout only matters for pages that keep animating.
    private static let settleTimeout: TimeInterval = 1.5
    private static let settleStep: Duration = .milliseconds(80)
    /// Horizontal bands the settle check compares one by one, so a single section still sliding in is not
    /// averaged away by the rest of a tall frame.
    private static let settleBands = 12
    /// Manual mode keeps every distinct poll, settled or not, so that consecutive frames still overlap while the
    /// user keeps scrolling; the interval bounds how far a fast scroll can travel between two kept frames.
    private static let manualPollInterval: Duration = .milliseconds(250)
    /// Wheel lines per step when a window ignores pixel-unit scroll events.
    private static let lineStep = 10

    public init(capture: CaptureServicing, windowList: WindowListProviding, notifications: NotificationPosting) {
        self.capture = capture
        self.windowList = windowList
        self.notifications = notifications
    }

    public func captureScrolling(window info: WindowInfo) async throws -> ScrollCaptureResult {
        let hud = ScrollHUDPanel(anchorWindow: info)
        defer { hud.orderOut(nil) }
        var escapePressed = false
        var returnPressed = false
        hud.onEscape = { escapePressed = true }
        hud.onReturn = { returnPressed = true }

        let started = Date()
        let deadline = started.addingTimeInterval(Self.maxDuration)
        let center = CGPoint(x: info.frame.midX, y: info.frame.midY)
        var auto = AXIsProcessTrusted()
        if !auto, !promptedForAccessibility {
            promptedForAccessibility = true
            notifications.post(title: "Manual scrolling mode",
                               body: "Allow Miracle Shot in System Settings > Privacy & Security > Accessibility for automatic scrolling.",
                               isError: false)
            // The key is the C global `kAXTrustedCheckOptionPrompt`; spelled out so Swift 6 does not flag the global.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
        }
        if auto, !(await bringToFront(info, center: center)) {
            auto = false
            notifications.post(title: "Manual scrolling mode",
                               body: "The window could not be brought to the front, so it has to be scrolled by hand.",
                               isError: false)
        }

        // The whole window is captured, chrome included; the user crops in the editor when needed.
        func grab() async throws -> Capture { try await capture.capture(.window(info)) }

        let frame0 = try await grab()
        var frames: [CGImage] = [frame0.image]

        if auto {
            hud.text = "Scrolling... \(frames.count) frames. Esc to stop"
            hud.show()
            // Warping alone does not tell the window server which window is now under the cursor; a mouse-moved
            // event does, and scroll events are routed by that.
            CGWarpMouseCursorPosition(center)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(50))
            var pixelStep = Int(info.frame.height * 0.75)
            var lineStep = Self.lineStep
            var useLineUnits = false
            var upwards = false

            while frames.count < Self.maxKeptFrames, Date() < deadline, !escapePressed {
                let amount = useLineUnits ? lineStep : pixelStep
                postScroll(step: upwards ? -amount : amount, units: useLineUnits ? .line : .pixel, at: center)
                let settled = try await waitForSettledFrame(grab, until: { escapePressed })
                let lastKept = frames[frames.count - 1]
                let delta = FrameDiff.difference(lastKept, settled)
                guard delta >= FrameDiff.samePageThreshold else {
                    // Some views ignore pixel-unit events: try classic wheel lines; and a view already at its
                    // end can still be scrolled the other way (the stitcher handles either direction).
                    if frames.count == 1, !useLineUnits { useLineUnits = true; continue }
                    if frames.count == 1, !upwards { upwards = true; continue }
                    break
                }
                frames.append(settled)
                hud.text = "Scrolling... \(frames.count) frames. Esc to stop"

                // How far did the view actually move? Apps map a wheel line to anything from a text line to a
                // page, so the step follows the measured shift: no overlap halves it, a small shift grows it.
                let shift = Self.measuredShift(from: lastKept, to: settled)
                let height = Double(settled.height)
                var factor = 1.0
                if shift == nil { factor = 0.5 } else if Double(shift!) > height * 0.85 { factor = 0.6 } else if Double(shift!) < height * 0.3 { factor = 1.5 }
                if useLineUnits { lineStep = max(1, min(60, Int(Double(lineStep) * factor))) } else { pixelStep = max(24, Int(Double(pixelStep) * factor)) }
                log.info("Scroll step: delta \(delta, format: .fixed(precision: 4), privacy: .public) shift \(shift ?? -1, privacy: .public) px, next step \(useLineUnits ? lineStep : pixelStep, privacy: .public) \(useLineUnits ? "lines" : "px", privacy: .public)")
            }

            if frames.count == 1, !escapePressed {
                auto = false
                log.info("Automatic scrolling had no effect; switching to manual mode")
                notifications.post(title: "Manual scrolling mode",
                                   body: "Automatic scrolling had no effect on this window, so it has to be scrolled by hand.",
                                   isError: false)
            }
        }

        if !auto {
            hud.text = "Scroll the window slowly with the mouse or trackpad, then press Return. Esc cancels."
            hud.show()

            while frames.count < Self.maxKeptFrames, Date() < deadline, !returnPressed, !escapePressed {
                try await Task.sleep(for: Self.manualPollInterval)
                guard !returnPressed, !escapePressed else { break }
                let polled = try await grab().image
                if FrameDiff.difference(frames[frames.count - 1], polled) >= FrameDiff.samePageThreshold {
                    frames.append(polled)
                    hud.text = "\(frames.count) of \(Self.maxKeptFrames) frames. Keep scrolling slowly, then press Return. Esc cancels."
                }
            }
            if escapePressed { throw CaptureError.cancelled }
        }

        guard let stitched = ImageStitcher.stitch(frames) else { throw CaptureError.noFrames }

        let elapsed = Date().timeIntervalSince(started)
        log.info("""
            Scrolling capture: mode=\(auto ? "auto" : "manual", privacy: .public) \
            frames=\(frames.count, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 2), privacy: .public)s \
            fallback=\(stitched.usedFallback, privacy: .public)
            """)
        dumpFramesIfRequested(frames: frames, stitched: stitched.image)

        let bounds = CGRect(origin: frame0.bounds.origin,
                            size: CGSize(width: frame0.bounds.width, height: CGFloat(stitched.image.height) / frame0.scaleFactor))
        let shot = Capture(image: stitched.image, sourceAppName: info.ownerName, sourceWindowTitle: info.title,
                           bounds: bounds, scaleFactor: frame0.scaleFactor)
        return ScrollCaptureResult(capture: shot, usedFallback: stitched.usedFallback)
    }

    // MARK: - Auto mode

    /// Scroll events land on whatever window is under the cursor, so the target has to be in front: activate its
    /// app and raise that window through Accessibility, then check the window list. Raising alone does not lift
    /// a window above another app's windows; activation alone does not pick the right window of the app.
    private func bringToFront(_ info: WindowInfo, center: CGPoint) async -> Bool {
        if SelectionGeometry.window(at: center, in: windowList.onScreenWindows())?.id != info.id {
            NSRunningApplication(processIdentifier: info.ownerPID)?.activate()
            raise(info)
            try? await Task.sleep(for: .milliseconds(250))
        }
        return SelectionGeometry.window(at: center, in: windowList.onScreenWindows())?.id == info.id
    }

    /// Performs AXRaise on the app's window whose position and size match `info`. Attribute and action names are
    /// spelled out: the `kAX...` C globals are not concurrency-safe under Swift 6.
    private func raise(_ info: WindowInfo) {
        let app = AXUIElementCreateApplication(info.ownerPID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXWindows" as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXPosition" as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(window, "AXSize" as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { continue }
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            if abs(position.x - info.frame.minX) < 2, abs(position.y - info.frame.minY) < 2,
               abs(size.width - info.frame.width) < 2, abs(size.height - info.frame.height) < 2 {
                AXUIElementPerformAction(window, "AXRaise" as CFString)
                return
            }
        }
    }

    /// Rows the content moved between two consecutive frames according to the stitcher, or nil when they do
    /// not overlap at all.
    private static func measuredShift(from previous: CGImage, to current: CGImage) -> Int? {
        guard let probe = ImageStitcher.stitch([previous, current]), !probe.usedFallback else { return nil }
        return probe.image.height - previous.height
    }

    private func postScroll(step: Int, units: CGScrollEventUnit, at location: CGPoint) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 1,
                                  wheel1: Int32(-step), wheel2: 0, wheel3: 0) else {
            log.error("Could not create the scroll event")
            return
        }
        event.location = location
        event.post(tap: .cghidEventTap)
        let cursor = CGEvent(source: nil)?.location ?? CGPoint(x: -1, y: -1)
        log.info("""
            Posted scroll of \(step, privacy: .public) \(units == .pixel ? "px" : "lines", privacy: .public) \
            at \(location.x, privacy: .public),\(location.y, privacy: .public); cursor at \(cursor.x, privacy: .public),\(cursor.y, privacy: .public)
            """)
    }

    /// Sleeps in `settleStep` increments, capturing and comparing to the previous poll each time, until every
    /// band of the image stops changing (below `FrameDiff.settledThreshold`), `settleTimeout` has elapsed, or
    /// `stop` says so, whichever comes first; either way the last captured frame is returned.
    private func waitForSettledFrame(_ grab: () async throws -> Capture, until stop: () -> Bool) async throws -> CGImage {
        var previousPoll: CGImage?
        let timeout = Date().addingTimeInterval(Self.settleTimeout)
        while true {
            try await Task.sleep(for: Self.settleStep)
            let polled = try await grab().image
            if let previousPoll {
                let delta = FrameDiff.maxBandDifference(previousPoll, polled, bands: Self.settleBands)
                log.info("Settle poll: delta \(delta, format: .fixed(precision: 4), privacy: .public)")
                if delta < FrameDiff.settledThreshold { return polled }
            }
            if stop() || Date() >= timeout {
                return polled
            }
            previousPoll = polled
        }
    }

    // MARK: - Debug dump

    /// Writes every kept frame and the stitched result as PNGs into a timestamped folder under
    /// `MIRACLE_SHOT_SCROLL_DUMP`, when set, so consecutive captures never overwrite each other.
    private func dumpFramesIfRequested(frames: [CGImage], stitched: CGImage) {
        guard let path = ProcessInfo.processInfo.environment["MIRACLE_SHOT_SCROLL_DUMP"], !path.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let directory = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
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
