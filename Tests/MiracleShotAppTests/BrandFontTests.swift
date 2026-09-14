import AppKit
import CoreText
import MiracleShotCore
import XCTest
@testable import MiracleShotUI

@MainActor
final class BrandFontTests: XCTestCase {
    func testBundleShipsThreeVariableFonts() throws {
        let dir = try XCTUnwrap(CoreResources.bundle.url(forResource: "fonts", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".ttf") }.sorted()
        XCTAssertEqual(files, ["Geologica-Variable.ttf", "JetBrainsMono-Variable.ttf", "Onest-Variable.ttf"])
    }

    func testBrandFacesResolveToBrandFamilies() {
        XCTAssertEqual(BrandFont.text(size: 12).familyName, "Onest")
        XCTAssertEqual(BrandFont.text(size: 12, weight: 600).familyName, "Onest")
        XCTAssertEqual(BrandFont.mono(size: 11).familyName, "JetBrains Mono")
        XCTAssertEqual(BrandFont.display(size: 20).familyName, "Geologica")
    }

    /// A same-named font installed on the machine must not satisfy the brand faces; only the bundled files do.
    func testBrandFacesComeFromTheBundle() throws {
        let dir = try XCTUnwrap(CoreResources.bundle.url(forResource: "fonts", withExtension: nil)).standardizedFileURL.path
        for font in [BrandFont.text(size: 12), BrandFont.mono(size: 11), BrandFont.display(size: 20)] {
            let url = try XCTUnwrap(CTFontCopyAttribute(font as CTFont, kCTFontURLAttribute) as? URL)
            XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(dir), "\(font.fontName) came from \(url.path)")
        }
    }

    func testRequestedSizeIsKept() {
        XCTAssertEqual(BrandFont.text(size: 13).pointSize, 13)
        XCTAssertEqual(BrandFont.mono(size: 11).pointSize, 11)
    }
}
