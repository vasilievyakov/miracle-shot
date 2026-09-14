import XCTest
@testable import MiracleShotCore

final class HotkeySpecTests: XCTestCase {
    func testParsesModifiersAndKeyCaseInsensitively() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "Cmd+Shift+4"))
        XCTAssertEqual(spec.key, "4")
        XCTAssertEqual(spec.modifiers, [.command, .shift])
    }

    func testAcceptsAliases() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "control + option + command + a"))
        XCTAssertEqual(spec.modifiers, [.control, .option, .command])
        XCTAssertEqual(spec.key, "a")
    }

    func testDescriptionIsCanonical() throws {
        XCTAssertEqual(HotkeySpec(parsing: "shift+CMD+4")?.description, "shift+cmd+4")
        XCTAssertEqual(HotkeySpec(parsing: "cmd+ctrl+opt+shift+space")?.description, "ctrl+opt+shift+cmd+space")
    }

    func testRejectsUnknownKeyOrMissingKey() {
        XCTAssertNil(HotkeySpec(parsing: "cmd+shift+"))
        XCTAssertNil(HotkeySpec(parsing: "cmd+shift+bogus"))
        XCTAssertNil(HotkeySpec(parsing: ""))
    }

    func testRejectsKeyWithoutModifiers() {
        XCTAssertNil(HotkeySpec(parsing: "4"))
    }

    func testCarbonValues() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "cmd+shift+4"))
        XCTAssertEqual(spec.carbonKeyCode, 21)
        XCTAssertEqual(spec.carbonModifiers, 256 | 512)
        XCTAssertEqual(KeyCodeMap.code(for: "space"), 49)
        XCTAssertEqual(KeyCodeMap.code(for: "f12"), 111)
        XCTAssertNil(KeyCodeMap.code(for: "nope"))
    }

    func testCodableRoundTrip() throws {
        let spec = try XCTUnwrap(HotkeySpec(parsing: "ctrl+shift+w"))
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(HotkeySpec.self, from: data), spec)
    }
}
