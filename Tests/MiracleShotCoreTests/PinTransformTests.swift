import XCTest
@testable import MiracleShotCore

final class PinTransformTests: XCTestCase {
    func testDefaultIsIdentity() {
        let t = PinTransform()
        XCTAssertEqual(t.opacity, 1)
        XCTAssertEqual(t.scale, 1)
        XCTAssertEqual(t, PinTransform.identity)
    }

    func testInitClampsOpacityBelowRange() {
        XCTAssertEqual(PinTransform(opacity: 0, scale: 1).opacity, 0.2)
    }

    func testInitClampsOpacityAboveRange() {
        XCTAssertEqual(PinTransform(opacity: 2, scale: 1).opacity, 1.0)
    }

    func testInitClampsScaleBelowRange() {
        XCTAssertEqual(PinTransform(opacity: 1, scale: 0.01).scale, 0.25)
    }

    func testInitClampsScaleAboveRange() {
        XCTAssertEqual(PinTransform(opacity: 1, scale: 100).scale, 4.0)
    }

    func testOpacityIncreasedAddsStep() {
        let t = PinTransform(opacity: 0.5, scale: 1)
        XCTAssertEqual(t.opacityIncreased().opacity, 0.6, accuracy: 1e-9)
    }

    func testOpacityIncreasedClampsAtMax() {
        let t = PinTransform(opacity: 1.0, scale: 1)
        XCTAssertEqual(t.opacityIncreased().opacity, 1.0)
    }

    func testOpacityDecreasedSubtractsStep() {
        let t = PinTransform(opacity: 0.5, scale: 1)
        XCTAssertEqual(t.opacityDecreased().opacity, 0.4, accuracy: 1e-9)
    }

    func testOpacityDecreasedClampsAtMin() {
        let t = PinTransform(opacity: 0.2, scale: 1)
        XCTAssertEqual(t.opacityDecreased().opacity, 0.2)
    }

    func testScaledUpMultipliesByDefaultStep() {
        let t = PinTransform(opacity: 1, scale: 1)
        XCTAssertEqual(t.scaledUp().scale, 1.25, accuracy: 1e-9)
    }

    func testScaledUpClampsAtMax() {
        let t = PinTransform(opacity: 1, scale: 4.0)
        XCTAssertEqual(t.scaledUp().scale, 4.0)
    }

    func testScaledDownDividesByDefaultStep() {
        let t = PinTransform(opacity: 1, scale: 1)
        XCTAssertEqual(t.scaledDown().scale, 0.8, accuracy: 1e-9)
    }

    func testScaledDownClampsAtMin() {
        let t = PinTransform(opacity: 1, scale: 0.25)
        XCTAssertEqual(t.scaledDown().scale, 0.25)
    }

    func testScaledUpWithCustomFactor() {
        let t = PinTransform(opacity: 1, scale: 1)
        XCTAssertEqual(t.scaledUp(by: 2).scale, 2, accuracy: 1e-9)
    }

    func testScaledDownWithCustomFactor() {
        let t = PinTransform(opacity: 1, scale: 1)
        XCTAssertEqual(t.scaledDown(by: 2).scale, 0.5, accuracy: 1e-9)
    }

    func testWheeledPositiveLinesMultipliesByStepPower() {
        let t = PinTransform(opacity: 1, scale: 1)
        XCTAssertEqual(t.wheeled(lines: 2).scale, pow(1.05, 2), accuracy: 1e-9)
    }

    func testWheeledFractionalLines() {
        let t = PinTransform(opacity: 1, scale: 2)
        XCTAssertEqual(t.wheeled(lines: 0.5).scale, 2 * pow(1.05, 0.5), accuracy: 1e-9)
    }

    func testWheeledNegativeLinesZoomsOut() {
        let t = PinTransform(opacity: 1, scale: 1)
        let wheeled = t.wheeled(lines: -2)
        XCTAssertEqual(wheeled.scale, pow(1.05, -2), accuracy: 1e-9)
        XCTAssertLessThan(wheeled.scale, 1)
    }

    func testWheeledClampsAtMax() {
        let t = PinTransform(opacity: 1, scale: 4.0)
        XCTAssertEqual(t.wheeled(lines: 100).scale, 4.0)
    }

    func testWheeledClampsAtMin() {
        let t = PinTransform(opacity: 1, scale: 0.25)
        XCTAssertEqual(t.wheeled(lines: -100).scale, 0.25)
    }

    func testStepAndRangeConstants() {
        XCTAssertEqual(PinTransform.opacityStep, 0.1)
        XCTAssertEqual(PinTransform.scaleStep, 1.25)
        XCTAssertEqual(PinTransform.wheelScaleStep, 1.05)
        XCTAssertEqual(PinTransform.opacityRange, 0.2...1.0)
        XCTAssertEqual(PinTransform.scaleRange, 0.25...4.0)
    }

    func testScaleLabelRounds() {
        XCTAssertEqual(PinTransform(opacity: 1, scale: 0.3333).scaleLabel, "33 %")
    }

    func testOpacityLabelRounds() {
        XCTAssertEqual(PinTransform(opacity: 0.666, scale: 1).opacityLabel, "67 %")
    }

    func testLabelsAtIdentity() {
        XCTAssertEqual(PinTransform.identity.scaleLabel, "100 %")
        XCTAssertEqual(PinTransform.identity.opacityLabel, "100 %")
    }

    func testNonFiniteValuesAreIgnored() {
        var t = PinTransform(opacity: .nan, scale: .infinity)
        XCTAssertEqual(t.opacity, 1)
        XCTAssertEqual(t.scale, 4)
        t.scale = 2
        t.scale = .nan
        XCTAssertEqual(t.scale, 2)
        XCTAssertEqual(t.wheeled(lines: .nan).scale, 2)
    }
}
