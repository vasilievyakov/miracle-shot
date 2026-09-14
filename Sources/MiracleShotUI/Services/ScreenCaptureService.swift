import AppKit
import MiracleShotCore
import ScreenCaptureKit

@MainActor
public final class ScreenCaptureService: CaptureServicing {
    public init() {}

    public func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    public func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    public func capture(_ selection: SelectionResult) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }

        switch selection {
        case .area(let rect, let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.displayNotFound
            }
            let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = Self.configuration()
            config.sourceRect = CGRect(x: rect.minX - display.frame.minX, y: rect.minY - display.frame.minY,
                                       width: rect.width, height: rect.height)
            config.width = Int((rect.width * scale).rounded())
            config.height = Int((rect.height * scale).rounded())
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Capture(image: image, bounds: rect, scaleFactor: scale)

        case .window(let info):
            guard let window = content.windows.first(where: { $0.windowID == info.id }) else {
                throw CaptureError.windowNotFound
            }
            let displayID = Self.displayID(containing: window.frame)
            let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = Self.configuration()
            // The default includes the window shadow, which would be squeezed into the frame-sized output.
            config.ignoreShadowsSingleWindow = true
            config.width = Int((window.frame.width * scale).rounded())
            config.height = Int((window.frame.height * scale).rounded())
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Capture(image: image, sourceAppName: window.owningApplication?.applicationName,
                           sourceWindowTitle: window.title, bounds: window.frame, scaleFactor: scale)
        }
    }

    public func captureDisplayUnderCursor() async throws -> Capture {
        guard let screen = NSScreen.underCursor else { throw CaptureError.displayNotFound }
        return try await captureDisplay(screen.displayID)
    }

    public func captureDisplay(_ displayID: CGDirectDisplayID) async throws -> Capture {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let scale = NSScreen.screen(for: displayID)?.backingScaleFactor ?? 2
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = Self.configuration()
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return Capture(image: image, bounds: display.frame, scaleFactor: scale)
    }

    private static func configuration() -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        c.showsCursor = false
        c.captureResolution = .best
        c.scalesToFit = false
        return c
    }

    private static func displayID(containing rect: CGRect) -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetDisplaysWithRect(rect, 16, &ids, &count)
        return count > 0 ? ids[0] : CGMainDisplayID()
    }
}
