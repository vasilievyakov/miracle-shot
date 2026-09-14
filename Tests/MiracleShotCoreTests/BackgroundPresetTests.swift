import Foundation
import XCTest
@testable import MiracleShotCore

final class BackgroundPresetTests: XCTestCase {
    private func sample() -> BackgroundPreset {
        BackgroundPreset(
            id: "sample", name: "Sample",
            fill: .linearGradient(stops: [GradientStop(color: BrandPalette.lime, location: 0),
                                          GradientStop(color: BrandPalette.limeDim, location: 1)], angle: 135),
            padding: 64, cornerRadius: 12,
            shadow: BackgroundShadow(blur: 40, offsetY: 16, opacity: 0.5))
    }

    func testBrandColorEncodesAsHexString() throws {
        let data = try JSONEncoder().encode(BrandPalette.lime)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"#d4ff3f\"")
        XCTAssertEqual(try JSONDecoder().decode(BrandColor.self, from: data), BrandPalette.lime)
    }

    func testBrandColorRejectsInvalidHex() {
        for bad in ["\"#zz\"", "\"#fff\"", "\"#gggggg\""] {
            XCTAssertThrowsError(try JSONDecoder().decode(BrandColor.self, from: Data(bad.utf8)), bad)
        }
    }

    func testSolidPresetRoundTripsThroughJSON() throws {
        let preset = BackgroundPreset(id: "s", name: "S", fill: .solid(color: BrandPalette.ink), padding: 8, cornerRadius: 4, shadow: nil)
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(try JSONDecoder().decode(BackgroundPreset.self, from: data), preset)
    }

    func testPresetRoundTripsThroughJSON() throws {
        let preset = sample()
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(try JSONDecoder().decode(BackgroundPreset.self, from: data), preset)
    }

    func testSolidFillDecodesFromReadableJSON() throws {
        let json = """
        {"id":"x","name":"X","fill":{"solid":{"color":"#0b0b0c"}},"padding":10,"cornerRadius":0}
        """
        let preset = try JSONDecoder().decode(BackgroundPreset.self, from: Data(json.utf8))
        XCTAssertEqual(preset.fill, .solid(color: BrandPalette.ink))
        XCTAssertNil(preset.shadow)
    }

    func testBuiltInPresetsLoadInOrder() {
        let presets = BackgroundPresetLibrary.builtIn()
        XCTAssertEqual(presets.map(\.id), ["lab-dark", "lime", "bone", "coral"])
        XCTAssertEqual(presets.map(\.name), ["Lab Dark", "Lime", "Bone", "Coral"])
        for preset in presets {
            XCTAssertGreaterThan(preset.padding, 0, preset.id)
            XCTAssertNotNil(preset.shadow, preset.id)
        }
    }

    func testBuiltInPresetsUseOnlyPaletteColors() {
        for preset in BackgroundPresetLibrary.builtIn() {
            for color in preset.colors {
                XCTAssertTrue(BrandPalette.all.contains(color), "\(preset.id) uses \(color.hex), not a palette token")
            }
        }
    }

    func testPresetWithoutGlowsDecodesToEmptyGlows() throws {
        let json = """
        {"id":"x","name":"X","fill":{"solid":{"color":"#0b0b0c"}},"padding":10,"cornerRadius":0}
        """
        let preset = try JSONDecoder().decode(BackgroundPreset.self, from: Data(json.utf8))
        XCTAssertEqual(preset.glows, [])
    }

    func testGlowsRoundTrip() throws {
        var preset = sample()
        preset.glows = [GradientGlow(color: BrandPalette.bone, x: 0.1, y: 0.9, radius: 0.4, opacity: 0.5)]
        let data = try JSONEncoder().encode(preset)
        XCTAssertEqual(try JSONDecoder().decode(BackgroundPreset.self, from: data), preset)
    }

    func testLoadAppendsUserPresetsAndSkipsBrokenFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ms-presets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try JSONEncoder().encode(sample()).write(to: dir.appendingPathComponent("sample.json"))
        try Data("not json".utf8).write(to: dir.appendingPathComponent("broken.json"))

        let presets = BackgroundPresetLibrary.load(userDirectory: dir)
        XCTAssertEqual(presets.count, BackgroundPresetLibrary.builtIn().count + 1)
        XCTAssertEqual(presets.last?.id, "sample")
    }

    func testLoadWithMissingUserDirectoryReturnsBuiltIns() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("ms-missing-\(UUID().uuidString)")
        XCTAssertEqual(BackgroundPresetLibrary.load(userDirectory: missing), BackgroundPresetLibrary.builtIn())
    }
}
