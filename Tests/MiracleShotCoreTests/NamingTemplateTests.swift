import XCTest
@testable import MiracleShotCore

final class NamingTemplateTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-09-14 14:05:09 UTC
    private let date = Date(timeIntervalSince1970: 1_789_394_709)

    func testDefaultPattern() {
        let name = NamingTemplate.default.fileName(date: date, appName: "Safari", sequence: 1, timeZone: utc)
        XCTAssertEqual(name, "Miracle Shot 2026-09-14 at 14.05.09.png")
    }

    func testAllTokens() {
        let t = NamingTemplate(pattern: "{app}_{date}_{time}_{seq}")
        XCTAssertEqual(t.fileName(date: date, appName: "Safari", sequence: 7, timeZone: utc),
                       "Safari_2026-09-14_14.05.09_7.png")
    }

    func testMissingAppFallsBackToScreen() {
        let t = NamingTemplate(pattern: "{app}")
        XCTAssertEqual(t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc), "Screen.png")
    }

    func testUnsafeCharactersAreReplaced() {
        let t = NamingTemplate(pattern: "{app}")
        XCTAssertEqual(t.fileName(date: date, appName: "Google/Chrome: Beta", sequence: 1, timeZone: utc),
                       "Google-Chrome- Beta.png")
    }

    func testEmptyPatternUsesDefault() {
        let t = NamingTemplate(pattern: "   ")
        XCTAssertEqual(t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc),
                       NamingTemplate.default.fileName(date: date, appName: nil, sequence: 1, timeZone: utc))
    }

    func testCustomExtension() {
        let t = NamingTemplate(pattern: "x")
        XCTAssertEqual(t.fileName(date: date, appName: nil, sequence: 1, fileExtension: "jpg", timeZone: utc), "x.jpg")
    }

    func testVeryLongNameIsTruncated() {
        let t = NamingTemplate(pattern: String(repeating: "a", count: 400))
        let name = t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc)
        XCTAssertLessThanOrEqual(name.utf8.count, 200 + ".png".utf8.count)
    }

    func testTruncationCountsBytesAndKeepsCharactersWhole() {
        let t = NamingTemplate(pattern: String(repeating: "\u{1F4F7}", count: 100))   // 100 x 4-byte camera emoji
        let name = t.fileName(date: date, appName: nil, sequence: 1, timeZone: utc)
        XCTAssertLessThanOrEqual(name.utf8.count, 200 + 4)
        XCTAssertEqual(String(name.dropLast(4)).unicodeScalars.count, 50)
    }

    func testCodableRoundTrip() throws {
        let t = NamingTemplate(pattern: "{date}-{seq}")
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(NamingTemplate.self, from: data), t)
    }
}
