import XCTest
@testable import MiracleShotCore

final class CoreSmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(MiracleShotCore.version.isEmpty)
    }

    func testCoreResourceBundleContainsPresetsFolder() {
        XCTAssertNotNil(CoreResources.bundle.url(forResource: "presets", withExtension: nil))
    }

    func testCoreResourceBundleContainsThreeFonts() throws {
        let dir = try XCTUnwrap(CoreResources.bundle.url(forResource: "fonts", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".ttf") }
        XCTAssertEqual(files.count, 3)
    }
}
