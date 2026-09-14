import XCTest
@testable import MiracleShotCore

final class HistoryPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_394_709)

    private func entry(secondsAgo: TimeInterval, path: String = "/tmp/Miracle Shot 2026-09-14 at 14.05.09.png") -> HistoryEntry {
        HistoryEntry(path: path, date: now.addingTimeInterval(-secondsAgo), width: 1200, height: 800, sourceApp: "Safari")
    }

    func testTitleIsFileNameWithoutExtension() {
        XCTAssertEqual(HistoryPresentation.title(for: entry(secondsAgo: 0)), "Miracle Shot 2026-09-14 at 14.05.09")
    }

    func testSubtitleCombinesSizeAndRelativeTime() {
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 5), now: now), "1200 × 800 · just now")
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 90), now: now), "1200 × 800 · 1 min ago")
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 3 * 3600), now: now), "1200 × 800 · 3 h ago")
        XCTAssertEqual(HistoryPresentation.subtitle(for: entry(secondsAgo: 2 * 86400), now: now), "1200 × 800 · 2 d ago")
    }

    func testRelativeTimeBoundaries() {
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 59), "just now")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 60), "1 min ago")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 3599), "59 min ago")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 3600), "1 h ago")
        XCTAssertEqual(HistoryPresentation.relativeTime(seconds: 86400), "1 d ago")
    }
}
