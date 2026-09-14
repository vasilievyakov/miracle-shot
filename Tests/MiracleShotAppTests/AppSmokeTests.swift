import SwiftUI
import XCTest
@testable import MiracleShotUI

final class AppSmokeTests: XCTestCase {
    func testUIModuleLinksAgainstCore() {
        XCTAssertEqual(MiracleShotUI.coreVersion, "0.1.0")
    }

    /// A grouped Form has no intrinsic height; the settings window once opened as a bare title bar.
    @MainActor
    func testSettingsViewHasAUsableHeight() {
        let hosting = NSHostingController(rootView: SettingsView(model: SettingsModel(settings: .default)))
        let size = hosting.view.fittingSize
        XCTAssertGreaterThan(size.height, 300)
        XCTAssertGreaterThan(size.width, 400)
    }
}
