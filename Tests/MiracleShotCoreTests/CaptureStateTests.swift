import XCTest
@testable import MiracleShotCore

final class CaptureStateTests: XCTestCase {
    func testHotkeyFromIdleStartsSelection() {
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .hotkey(.area)), .selecting(.area))
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .hotkey(.window)), .selecting(.window))
    }

    func testFullScreenHotkeySkipsSelection() {
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .hotkey(.fullScreen)), .capturing)
    }

    func testHotkeyWhileSelectingIsIgnored() {
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.area), .hotkey(.window)), .selecting(.area))
    }

    func testHotkeyWhileCapturingIsIgnored() {
        XCTAssertEqual(CaptureStateMachine.reduce(.capturing, .hotkey(.area)), .capturing)
    }

    func testEscapeCancelsSelection() {
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.window), .selectionCancelled), .idle)
    }

    func testSelectionMadeStartsCapture() {
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.area), .selectionMade), .capturing)
    }

    func testCaptureOutcomes() {
        XCTAssertEqual(CaptureStateMachine.reduce(.capturing, .captureSucceeded), .previewing)
        XCTAssertEqual(CaptureStateMachine.reduce(.capturing, .captureFailed), .idle)
    }

    func testPreviewDismissReturnsToIdle() {
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .previewDismissed), .idle)
    }

    func testHotkeyWhilePreviewingStartsNewCapture() {
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .hotkey(.area)), .selecting(.area))
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .hotkey(.fullScreen)), .capturing)
    }

    func testIrrelevantEventsLeaveStateUnchanged() {
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .selectionMade), .idle)
        XCTAssertEqual(CaptureStateMachine.reduce(.idle, .captureSucceeded), .idle)
        XCTAssertEqual(CaptureStateMachine.reduce(.selecting(.area), .captureFailed), .selecting(.area))
        XCTAssertEqual(CaptureStateMachine.reduce(.previewing, .selectionCancelled), .previewing)
    }

    func testCanStartCaptureOnlyFromIdleOrPreviewing() {
        XCTAssertTrue(CaptureState.idle.canStartCapture)
        XCTAssertTrue(CaptureState.previewing.canStartCapture)
        XCTAssertFalse(CaptureState.selecting(.area).canStartCapture)
        XCTAssertFalse(CaptureState.capturing.canStartCapture)
    }
}
