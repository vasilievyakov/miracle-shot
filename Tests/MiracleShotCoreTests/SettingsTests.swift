import XCTest
@testable import MiracleShotCore

final class SettingsTests: XCTestCase {
    private var createdURLs: [URL] = []

    override func tearDown() {
        for url in createdURLs {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("broken"))
        }
        createdURLs.removeAll()
    }

    private func tempURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        createdURLs.append(url)
        return url
    }

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
        let url = tempURL()
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
        let url = tempURL()
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

    func testRelativeOrEmptySaveDirectoryFallsBackToPictures() {
        var s = Settings.default
        s.saveDirectoryPath = "not/absolute"
        XCTAssertEqual(s.saveDirectoryURL, Settings.fallbackSaveDirectory)
        s.saveDirectoryPath = ""
        XCTAssertEqual(s.saveDirectoryURL, Settings.fallbackSaveDirectory)
    }

    func testWrongTypedFieldQuarantinesFileAndLoadsDefault() throws {
        let url = tempURL()
        try Data(#"{"previewTimeout": "six"}"#.utf8).write(to: url)
        XCTAssertEqual(Settings.load(from: url), .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("broken").path))
    }
}
