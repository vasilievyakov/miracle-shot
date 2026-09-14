import XCTest
@testable import MiracleShotCore

final class BrandPaletteTests: XCTestCase {
    func testHexParsing() throws {
        let c = try XCTUnwrap(BrandColor(hex: "#d4ff3f"))
        XCTAssertEqual(c.red, 0xd4 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.green, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.blue, 0x3f / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.hex, "#d4ff3f")
    }

    func testHexRejectsGarbage() {
        XCTAssertNil(BrandColor(hex: "d4ff3"))
        XCTAssertNil(BrandColor(hex: "#zzzzzz"))
    }

    func testTokensMatchAgenticLab() {
        XCTAssertEqual(BrandPalette.ink.hex, "#0b0b0c")
        XCTAssertEqual(BrandPalette.ink2.hex, "#141416")
        XCTAssertEqual(BrandPalette.ink3.hex, "#1c1c1f")
        XCTAssertEqual(BrandPalette.bone.hex, "#f3f0e8")
        XCTAssertEqual(BrandPalette.boneDim.hex, "#b8b4a8")
        XCTAssertEqual(BrandPalette.boneFaint.hex, "#6f6c63")
        XCTAssertEqual(BrandPalette.lime.hex, "#d4ff3f")
        XCTAssertEqual(BrandPalette.limeDim.hex, "#9bbf2a")
        XCTAssertEqual(BrandPalette.coral.hex, "#ff5a36")
        XCTAssertEqual(BrandPalette.line.hex, "#2a2a2d")
    }

    func testCGColorIsSRGBWithAlpha() {
        let cg = BrandPalette.lime.cgColor(alpha: 0.5)
        XCTAssertEqual(cg.alpha, 0.5, accuracy: 0.001)
        XCTAssertEqual(cg.numberOfComponents, 4)
    }
}
