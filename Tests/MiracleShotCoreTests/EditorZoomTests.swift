import XCTest
@testable import MiracleShotCore

final class EditorZoomTests: XCTestCase {
    // MARK: fit

    func testFitNeverExceedsNatural() {
        // Unconstrained fit would be min(752/1000, 552/500) = min(0.752, 1.104) = 0.752, but natural caps it.
        let scale = EditorZoom.fit.scale(imageSize: CGSize(width: 1000, height: 500),
                                          viewSize: CGSize(width: 800, height: 600), padding: 24, natural: 0.5)
        XCTAssertEqual(scale, 0.5)
    }

    func testFitOfTallScrollingCaptureFitsWidthInsteadOfHeight() {
        // heightFit (552/8000 = 0.069) is far below widthFit/2 (752/400/2 = 0.94): a scrolling capture, so fit
        // the width and let the rest scroll rather than shrinking to fit the whole strip.
        let scale = EditorZoom.fit.scale(imageSize: CGSize(width: 400, height: 8000),
                                          viewSize: CGSize(width: 800, height: 600), padding: 24, natural: 2)
        XCTAssertEqual(scale, (800 - 48) / 400, accuracy: 0.0001)
    }

    func testFitOfWideCaptureFitsHeightInsteadOfWidth() {
        // Symmetric case: a very wide image fits the height and scrolls horizontally.
        let scale = EditorZoom.fit.scale(imageSize: CGSize(width: 8000, height: 400),
                                          viewSize: CGSize(width: 800, height: 600), padding: 24, natural: 2)
        XCTAssertEqual(scale, (600 - 48) / 400, accuracy: 0.0001)
    }

    func testFitOfOrdinaryImageFitsWhicheverAxisBinds() {
        let scale = EditorZoom.fit.scale(imageSize: CGSize(width: 4000, height: 2000),
                                          viewSize: CGSize(width: 1000, height: 800), padding: 24, natural: 1)
        XCTAssertEqual(scale, min((1000 - 48) / 4000, (800 - 48) / 2000), accuracy: 0.0001)
    }

    // MARK: fixed

    func testFixedClampsToPresetRange() {
        XCTAssertEqual(EditorZoom.fixed(100).scale(imageSize: CGSize(width: 10, height: 10),
                                                     viewSize: CGSize(width: 100, height: 100), padding: 0, natural: 1), 4)
        XCTAssertEqual(EditorZoom.fixed(0.001).scale(imageSize: CGSize(width: 10, height: 10),
                                                       viewSize: CGSize(width: 100, height: 100), padding: 0, natural: 1), 0.1)
    }

    func testFixedWithinRangeIsUnchanged() {
        XCTAssertEqual(EditorZoom.fixed(0.6).scale(imageSize: CGSize(width: 10, height: 10),
                                                     viewSize: CGSize(width: 100, height: 100), padding: 0, natural: 1), 0.6)
    }

    // MARK: zoomedIn / zoomedOut

    func testZoomedInMovesToNextPresetAboveNatural() {
        // currentScale 0.5 == 1x natural(0.5); the next preset above 1 is 1.5, i.e. 0.75.
        XCTAssertEqual(EditorZoom.fit.zoomedIn(currentScale: 0.5, natural: 0.5), .fixed(0.75))
    }

    func testZoomedInAtTopPresetStays() {
        XCTAssertEqual(EditorZoom.fixed(4).zoomedIn(currentScale: 4, natural: 1), .fixed(4))
    }

    func testZoomedOutFromNonPresetScalePicksNextPresetBelow() {
        // currentScale 0.6 sits between the 0.5 and 0.75 presets; zooming out lands on 0.5.
        XCTAssertEqual(EditorZoom.fit.zoomedOut(currentScale: 0.6, natural: 1), .fixed(0.5))
    }

    func testZoomedOutAtBottomPresetStays() {
        XCTAssertEqual(EditorZoom.fixed(0.1).zoomedOut(currentScale: 0.1, natural: 1), .fixed(0.1))
    }

    // MARK: scaled

    func testScaledMultipliesAndClamps() {
        XCTAssertEqual(EditorZoom.scaled(currentScale: 1, by: 1.5, natural: 1), .fixed(1.5))
        XCTAssertEqual(EditorZoom.scaled(currentScale: 3.9, by: 2, natural: 1), .fixed(4))
        XCTAssertEqual(EditorZoom.scaled(currentScale: 0.2, by: 0.1, natural: 1), .fixed(0.1))
    }

    // MARK: label

    func testLabelRoundsToWholePercent() {
        XCTAssertEqual(EditorZoom.label(scale: 1, natural: 1), "100%")
        XCTAssertEqual(EditorZoom.label(scale: 0.373, natural: 1), "37%")
        XCTAssertEqual(EditorZoom.label(scale: 0.5, natural: 2), "25%")
    }
}
