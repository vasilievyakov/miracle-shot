/// User-triggerable actions bound to hotkeys. Later phases append cases; never reorder or rename existing ones,
/// the raw values are persisted in settings.json.
public enum CaptureAction: String, Codable, Sendable, CaseIterable, Hashable {
    case captureArea
    case captureWindow
    case captureFullScreen
    case captureScrolling

    public var captureMode: CaptureMode {
        switch self {
        case .captureArea: return .area
        case .captureWindow: return .window
        case .captureFullScreen: return .fullScreen
        case .captureScrolling: return .window
        }
    }

    public var title: String {
        switch self {
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .captureFullScreen: return "Capture Full Screen"
        case .captureScrolling: return "Capture Scrolling Window"
        }
    }
}
