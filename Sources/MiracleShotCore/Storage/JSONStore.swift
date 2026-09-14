import Foundation
import os

/// JSON persistence with one rule: a corrupt file is never fatal. It is renamed to `<name>.broken` and treated as missing.
public enum JSONStore {
    private static let log = Logger(subsystem: "agency.blackbloom.miracleshot", category: "storage")

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Exists but unreadable (permissions, I/O): keep the file, continue with defaults.
            log.error("Cannot read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        do {
            return try decoder().decode(T.self, from: data)
        } catch {
            log.error("Corrupt \(url.lastPathComponent, privacy: .public), quarantined as .broken: \(error.localizedDescription, privacy: .public)")
            quarantine(url)
            return nil
        }
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalFormatter.string(from: date))
        }
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = fractionalFormatter.date(from: string) ?? wholeSecondFormatter.date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO8601 date: \(string)"))
        }
        return d
    }

    /// ISO8601 with fractional seconds, so `Date()` round-trips without losing sub-second precision.
    /// `ISO8601DateFormatter` is not `Sendable`, so a fresh instance is made per use instead of a static.
    private static var fractionalFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    /// Accepts files written without fractional seconds.
    private static var wholeSecondFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private static func quarantine(_ url: URL) {
        let broken = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.moveItem(at: url, to: broken)
    }
}
