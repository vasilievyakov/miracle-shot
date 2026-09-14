import Foundation

public enum HistoryPresentation {
    public static func title(for entry: HistoryEntry) -> String {
        ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    public static func subtitle(for entry: HistoryEntry, now: Date = Date()) -> String {
        "\(entry.width) × \(entry.height) · \(relativeTime(seconds: now.timeIntervalSince(entry.date)))"
    }

    public static func relativeTime(seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(s / 60) min ago"
        case ..<86400: return "\(s / 3600) h ago"
        default: return "\(s / 86400) d ago"
        }
    }
}
