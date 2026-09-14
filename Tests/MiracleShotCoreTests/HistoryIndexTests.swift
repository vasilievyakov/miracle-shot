import XCTest
@testable import MiracleShotCore

final class HistoryIndexTests: XCTestCase {
    private var createdURLs: [URL] = []

    override func tearDown() {
        createdURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        createdURLs.removeAll()
    }

    private func tempURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        createdURLs.append(url)
        return url
    }

    private func entry(_ n: Int) -> HistoryEntry {
        HistoryEntry(id: UUID(), path: "/tmp/\(n).png", date: Date(timeIntervalSince1970: TimeInterval(n)),
                     width: 10, height: 10, sourceApp: nil)
    }

    func testAppendPutsNewestFirst() {
        var index = HistoryIndex(limit: 10)
        index.append(entry(1))
        index.append(entry(2))
        XCTAssertEqual(index.entries.map(\.path), ["/tmp/2.png", "/tmp/1.png"])
    }

    func testAppendTrimsToLimit() {
        var index = HistoryIndex(limit: 2)
        (1...3).forEach { index.append(entry($0)) }
        XCTAssertEqual(index.entries.map(\.path), ["/tmp/3.png", "/tmp/2.png"])
    }

    func testRemoveById() {
        var index = HistoryIndex(limit: 10)
        let e = entry(1)
        index.append(e)
        index.remove(id: e.id)
        XCTAssertTrue(index.entries.isEmpty)
    }

    func testLoadMissingGivesEmptyWithLimit() {
        let url = tempURL()
        let index = HistoryIndex.load(from: url, limit: 7)
        XCTAssertTrue(index.entries.isEmpty)
        XCTAssertEqual(index.limit, 7)
    }

    func testSaveAndLoadRoundTrip() throws {
        let url = tempURL()
        var index = HistoryIndex(limit: 5)
        index.append(entry(1))
        try index.save(to: url)
        let loaded = HistoryIndex.load(from: url, limit: 5)
        XCTAssertEqual(loaded, index)
    }

    func testLoadAppliesNewLimit() throws {
        let url = tempURL()
        var index = HistoryIndex(limit: 10)
        (1...5).forEach { index.append(entry($0)) }
        try index.save(to: url)
        XCTAssertEqual(HistoryIndex.load(from: url, limit: 2).entries.count, 2)
    }

    func testNegativeLimitIsClampedToZero() {
        var index = HistoryIndex(limit: -3)
        index.append(entry(1))
        XCTAssertEqual(index.limit, 0)
        XCTAssertTrue(index.entries.isEmpty)
    }
}
