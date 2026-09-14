import Foundation
import MiracleShotCore

/// Placeholder until the floating preview exists: reports dismissal right away so the state machine returns to idle.
@MainActor
public final class ImmediateDismissPreview: PreviewPresenting {
    public init() {}
    public func show(capture: Capture, fileURL: URL?, onDismiss: @escaping @MainActor () -> Void) {
        onDismiss()
    }
}
