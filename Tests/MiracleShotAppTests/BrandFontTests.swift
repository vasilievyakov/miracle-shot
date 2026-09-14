import AppKit
import XCTest
@testable import MiracleShotUI

final class BrandFontTests: XCTestCase {
    func testBundleShipsThreeVariableFonts() throws {
        let dir = try XCTUnwrap(UIResources.bundle.url(forResource: "fonts", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".ttf") }.sorted()
        XCTAssertEqual(files, ["Geologica-Variable.ttf", "JetBrainsMono-Variable.ttf", "Onest-Variable.ttf"])
    }

    func testBrandFacesResolveToBrandFamilies() {
        XCTAssertEqual(BrandFont.text(size: 12).familyName, "Onest")
        XCTAssertEqual(BrandFont.text(size: 12, weight: 600).familyName, "Onest")
        XCTAssertEqual(BrandFont.mono(size: 11).familyName, "JetBrains Mono")
        XCTAssertEqual(BrandFont.display(size: 20).familyName, "Geologica")
    }

    func testRequestedSizeIsKept() {
        XCTAssertEqual(BrandFont.text(size: 13).pointSize, 13)
        XCTAssertEqual(BrandFont.mono(size: 11).pointSize, 11)
    }
}
