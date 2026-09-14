import XCTest
@testable import MiracleShotCore

final class PreviewTimingTests: XCTestCase {
    func testStartsRunningWithFullDuration() {
        let t = PreviewTiming(duration: 6, now: 100)
        XCTAssertEqual(t.phase, .running(deadline: 106))
        XCTAssertEqual(t.remaining(now: 102), 4)
    }

    func testTickBeforeDeadlineDoesNothing() {
        var t = PreviewTiming(duration: 6, now: 100)
        XCTAssertFalse(t.tick(now: 105.9))
        XCTAssertEqual(t.phase, .running(deadline: 106))
    }

    func testTickAtDeadlineExpiresOnce() {
        var t = PreviewTiming(duration: 6, now: 100)
        XCTAssertTrue(t.tick(now: 106))
        XCTAssertEqual(t.phase, .expired)
        XCTAssertFalse(t.tick(now: 200))
    }

    func testHoverPausesAndResumesWithRemainingTime() {
        var t = PreviewTiming(duration: 6, now: 100)
        t.hoverBegan(now: 104)
        XCTAssertEqual(t.phase, .paused(remaining: 2))
        XCTAssertFalse(t.tick(now: 500))
        t.hoverEnded(now: 500)
        XCTAssertEqual(t.phase, .running(deadline: 502))
        XCTAssertTrue(t.tick(now: 502))
    }

    func testHoverAfterExpiryIsNoop() {
        var t = PreviewTiming(duration: 1, now: 0)
        _ = t.tick(now: 1)
        t.hoverBegan(now: 2)
        XCTAssertEqual(t.phase, .expired)
    }

    func testRemainingNeverNegative() {
        let t = PreviewTiming(duration: 1, now: 0)
        XCTAssertEqual(t.remaining(now: 50), 0)
    }

    func testDoubleHoverBeganIsIdempotent() {
        var t = PreviewTiming(duration: 6, now: 100)
        t.hoverBegan(now: 104)
        t.hoverBegan(now: 105)
        XCTAssertEqual(t.phase, .paused(remaining: 2))
    }

    func testHoverEndedWithoutHoverBeganIsNoop() {
        var t = PreviewTiming(duration: 6, now: 100)
        t.hoverEnded(now: 103)
        XCTAssertEqual(t.phase, .running(deadline: 106))
    }
}
