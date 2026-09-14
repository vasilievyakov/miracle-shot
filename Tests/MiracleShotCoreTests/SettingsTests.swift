import XCTest
@testable import MiracleShotCore

final class SettingsTests: XCTestCase {
    func testDefaultsAreSane() {
        let s = Settings.default
        XCTAssertEqual(s.hotkeys[.captureArea]?.description, "shift+cmd+1")
        XCTAssertEqual(s.hotkeys[.captureWindow]?.description, "shift+cmd+2")
        XCTAssertEqual(s.hotkeys[.captureFullScreen]?.description, "shift+cmd+0")
        XCTAssertEqual(s.previewTimeout, 6)
        XCTAssertEqual(s.historyLimit, 50)
        XCTAssertEqual(s.namingTemplate, .default)
        XCTAssertTrue(s.saveDirectoryURL.path.hasSuffix("/Pictures/Miracle Shot"))
    }

    func testRoundTrip() throws {
        var s = Settings.default
        s.previewTimeout = 3
        s.hotkeys[.captureArea] = HotkeySpec(parsing: "ctrl+opt+s")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try s.save(to: url)
        XCTAssertEqual(Settings.load(from: url), s)
    }

    func testMissingFieldsFallBackToDefaults() throws {
        let data = Data(#"{"previewTimeout": 2}"#.utf8)
        let s = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s.previewTimeout, 2)
        XCTAssertEqual(s.historyLimit, Settings.default.historyLimit)
        XCTAssertEqual(s.hotkeys, Settings.default.hotkeys)
    }

    func testMissingOrCorruptFileLoadsDefault() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        XCTAssertEqual(Settings.load(from: url), .default)
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(Settings.load(from: url), .default)
    }

    func testTildeIsExpandedInSaveDirectory() {
        var s = Settings.default
        s.saveDirectoryPath = "~/Desktop/Shots"
        XCTAssertFalse(s.saveDirectoryURL.path.contains("~"))
        XCTAssertTrue(s.saveDirectoryURL.path.hasSuffix("/Desktop/Shots"))
    }
}
