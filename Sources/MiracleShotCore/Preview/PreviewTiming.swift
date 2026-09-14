import Foundation

/// Auto-dismiss timer state for the floating preview. Hover pauses it, leaving resumes it.
/// Time is injected as `TimeInterval` so the logic is testable without clocks.
public struct PreviewTiming: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case running(deadline: TimeInterval)
        case paused(remaining: TimeInterval)
        case expired
    }

    public let duration: TimeInterval
    public private(set) var phase: Phase

    public init(duration: TimeInterval, now: TimeInterval) {
        self.duration = duration
        self.phase = .running(deadline: now + duration)
    }

    public func remaining(now: TimeInterval) -> TimeInterval {
        switch phase {
        case .running(let deadline): return max(0, deadline - now)
        case .paused(let remaining): return remaining
        case .expired: return 0
        }
    }

    public mutating func hoverBegan(now: TimeInterval) {
        if case .running(let deadline) = phase {
            phase = .paused(remaining: max(0, deadline - now))
        }
    }

    public mutating func hoverEnded(now: TimeInterval) {
        if case .paused(let remaining) = phase {
            phase = .running(deadline: now + remaining)
        }
    }

    /// Returns true exactly once, when the deadline is reached.
    public mutating func tick(now: TimeInterval) -> Bool {
        guard case .running(let deadline) = phase, now >= deadline else { return false }
        phase = .expired
        return true
    }
}
