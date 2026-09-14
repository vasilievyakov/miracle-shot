import XCTest
@testable import MiracleShotCore

final class OKLabTests: XCTestCase {
    func testBlackAndWhiteAnchorLightness() {
        XCTAssertEqual(OKLab.from(BrandColor(red: 0, green: 0, blue: 0)).l, 0, accuracy: 1e-4)
        XCTAssertEqual(OKLab.from(BrandColor(red: 1, green: 1, blue: 1)).l, 1, accuracy: 1e-3)
    }

    func testMidGrayIsPerceptuallyAboveHalf() {
        // sRGB 50 percent gray sits near L = 0.6 in OKLab, not 0.5: that is the whole point of the space.
        let l = OKLab.from(BrandColor(hex: "#808080")!).l
        XCTAssertEqual(l, 0.6, accuracy: 0.02)
    }

    func testRoundTripsPaletteColors() {
        for color in BrandPalette.all {
            let back = OKLab.from(color).toSRGB()
            XCTAssertEqual(back.red, color.red, accuracy: 0.002, color.hex)
            XCTAssertEqual(back.green, color.green, accuracy: 0.002, color.hex)
            XCTAssertEqual(back.blue, color.blue, accuracy: 0.002, color.hex)
        }
    }

    func testMixIsLinearInLab() {
        let a = OKLab.from(BrandPalette.coral), b = OKLab.from(BrandPalette.ink2)
        let mid = OKLab.mix(a, b, 0.5)
        XCTAssertEqual(mid.l, (a.l + b.l) / 2, accuracy: 1e-9)
        XCTAssertEqual(mid.a, (a.a + b.a) / 2, accuracy: 1e-9)
    }

    func testToSRGBClampsOutOfGamut() {
        let hot = OKLab(l: 1.2, a: 0.4, b: 0.4).toSRGB()
        XCTAssertLessThanOrEqual(hot.red, 1)
        XCTAssertGreaterThanOrEqual(hot.blue, 0)
    }
}
