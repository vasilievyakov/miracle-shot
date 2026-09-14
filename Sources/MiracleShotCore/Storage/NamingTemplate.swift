import Foundation

/// File name pattern with `{date}`, `{time}`, `{app}` and `{seq}` tokens.
public struct NamingTemplate: Sendable, Equatable, Codable {
    public static let `default` = NamingTemplate(pattern: "Miracle Shot {date} at {time}")
    /// Maximum length of the base name in UTF-8 bytes, leaving room for the extension under the 255-byte APFS limit.
    public static let maxBaseNameLength = 200

    public var pattern: String

    public init(pattern: String) {
        self.pattern = pattern
    }

    public func fileName(date: Date, appName: String?, sequence: Int,
                         fileExtension: String = "png", timeZone: TimeZone = .current) -> String {
        let effective = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.default.pattern : pattern
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = timeZone
        timeFormatter.dateFormat = "HH.mm.ss"

        let sanitizedApp = Self.sanitize(appName ?? "")
        var name = effective
            .replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))
            .replacingOccurrences(of: "{time}", with: timeFormatter.string(from: date))
            .replacingOccurrences(of: "{app}", with: sanitizedApp.isEmpty ? "Screen" : sanitizedApp)
            .replacingOccurrences(of: "{seq}", with: String(sequence))
        name = Self.sanitize(name)
        // APFS limits a path component to 255 UTF-8 bytes; truncate by bytes, never mid-character.
        while name.utf8.count > Self.maxBaseNameLength {
            name.removeLast()
        }
        return "\(name).\(fileExtension)"
    }

    /// Replaces path separators and colons, which Finder cannot display, with dashes.
    static func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
