import XCTest
@testable import MiracleShotCore

final class CoreSmokeTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertFalse(MiracleShotCore.version.isEmpty)
    }

    func testCoreResourceBundleContainsPresetsFolder() {
        XCTAssertNotNil(CoreResources.bundle.url(forResource: "presets", withExtension: nil))
    }
}
