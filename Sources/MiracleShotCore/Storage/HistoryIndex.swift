import Foundation

public struct HistoryEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let path: String
    public let date: Date
    public let width: Int
    public let height: Int
    public let sourceApp: String?

    public init(id: UUID = UUID(), path: String, date: Date, width: Int, height: Int, sourceApp: String?) {
        self.id = id
        self.path = path
        self.date = date
        self.width = width
        self.height = height
        self.sourceApp = sourceApp
    }
}

/// Newest-first list of recent captures, capped at `limit`.
public struct HistoryIndex: Codable, Sendable, Equatable {
    public private(set) var entries: [HistoryEntry]
    public let limit: Int

    public init(limit: Int, entries: [HistoryEntry] = []) {
        self.limit = max(0, limit)
        self.entries = Array(entries.prefix(self.limit))
    }

    public mutating func append(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// The `limit` stored in the file is ignored on purpose: the caller's current settings win over a stale value.
    public static func load(from url: URL, limit: Int) -> HistoryIndex {
        let stored = JSONStore.load(HistoryIndex.self, from: url)
        return HistoryIndex(limit: limit, entries: stored?.entries ?? [])
    }

    public func save(to url: URL) throws {
        try JSONStore.save(self, to: url)
    }
}
