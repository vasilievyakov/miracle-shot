/// Events that drive the capture flow. Produced by hotkeys, the selection overlay, the capture service and the preview.
public enum CaptureEvent: Sendable, Equatable {
    case hotkey(CaptureMode)
    case selectionCancelled
    case selectionMade
    case captureSucceeded
    case captureFailed
    case previewDismissed
}

public enum CaptureState: Sendable, Equatable {
    case idle
    case selecting(CaptureMode)
    case capturing
    case previewing

    /// A new capture may only start when nothing is in flight. Previewing counts as free.
    public var canStartCapture: Bool {
        switch self {
        case .idle, .previewing: return true
        case .selecting, .capturing: return false
        }
    }
}

/// Pure transition table. Unknown combinations leave the state untouched.
public enum CaptureStateMachine {
    public static func reduce(_ state: CaptureState, _ event: CaptureEvent) -> CaptureState {
        switch (state, event) {
        case (.idle, .hotkey(let mode)), (.previewing, .hotkey(let mode)):
            return mode == .fullScreen ? .capturing : .selecting(mode)
        case (.selecting, .selectionCancelled):
            return .idle
        case (.selecting, .selectionMade):
            return .capturing
        case (.capturing, .captureSucceeded):
            return .previewing
        case (.capturing, .captureFailed):
            return .idle
        case (.previewing, .previewDismissed):
            return .idle
        default:
            return state
        }
    }
}
