import CoreGraphics
import Foundation
import MiracleShotCore

/// What the selection overlay hands back. Rect is in CG global coordinates.
public enum SelectionResult: Sendable, Equatable {
    case area(rect: CGRect, displayID: CGDirectDisplayID)
    case window(WindowInfo)
}

public enum CaptureError: Error, Equatable, Sendable {
    case permissionDenied
    case displayNotFound
    case windowNotFound
    case emptyImage
}

@MainActor public protocol CaptureServicing: AnyObject {
    func hasPermission() -> Bool
    func requestPermission()
    func capture(_ selection: SelectionResult) async throws -> Capture
    /// Full display under the mouse cursor.
    func captureDisplayUnderCursor() async throws -> Capture
}

@MainActor public protocol SelectionPresenting: AnyObject {
    /// Shows the overlay and suspends until the user finishes or cancels. `nil` means cancelled.
    func present(mode: CaptureMode) async -> SelectionResult?
}

@MainActor public protocol ClipboardServicing: AnyObject {
    func copy(_ capture: Capture)
}

@MainActor public protocol FileSaving: AnyObject {
    /// Writes the capture as PNG and returns the final URL.
    func save(_ capture: Capture, named fileName: String, in directory: URL) throws -> URL
}

@MainActor public protocol NotificationPosting: AnyObject {
    func post(title: String, body: String, isError: Bool)
}

@MainActor public protocol PreviewPresenting: AnyObject {
    func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void)
}
