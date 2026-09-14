import XCTest
@testable import MiracleShotUI

final class AppSmokeTests: XCTestCase {
    func testUIModuleLinksAgainstCore() {
        XCTAssertEqual(MiracleShotUI.coreVersion, "0.1.0")
    }
}
