// Last edited: 2026-09-24 15:09 PT

import Foundation

/// The one timer's state: idle, or an active timer. `ActiveTimerStore` saves it as JSON.
///
/// It stores dates and the remaining time, never a tick count, so sleep and relaunch cannot make it drift.
enum TimerState: Codable, Equatable, Sendable {
    case idle
    case active(ActiveTimer)

    /// The active timer, or nil when idle.
    var activeTimer: ActiveTimer? {
        if case let .active(timer) = self {
            timer
        } else {
            nil
        }
    }
}

/// A timer that runs, is paused, or is past zero (overtime). The fields outside `phase` are the same in every phase.
///
/// Until overtime, `activeSeconds(at:) + remaining(at:) == plannedSeconds`. The UI can use that for a progress bar.
struct ActiveTimer: Codable, Equatable, Sendable {
    enum Phase: Codable, Equatable, Sendable {
        /// Counts down to `endDate`.
        case running(endDate: Date)
        /// Stopped for now, with `remaining` seconds left.
        case paused(remaining: TimeInterval)
        /// Past zero since `since` (the old end date). It counts up.
        case overtime(since: Date)
    }

    var taskID: UUID
    /// The open `TimerSession` for this run. The engine closes this same session, also after a relaunch.
    var sessionID: UUID
    /// The first duration plus every extension.
    var plannedSeconds: TimeInterval
    var startedAt: Date
    /// Active time up to `lastResumedAt`, or all active time while paused.
    var accumulatedActiveSeconds: TimeInterval
    /// When the timer last started or resumed. Nil while paused, so paused time does not count.
    var lastResumedAt: Date?
    var phase: Phase

    /// Seconds left before zero. 0 in overtime.
    func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case let .running(endDate): max(0, endDate.timeIntervalSince(now))
        case let .paused(remaining): remaining
        case .overtime: 0
        }
    }

    /// Seconds past zero. 0 when not in overtime.
    func overtime(at now: Date) -> TimeInterval {
        if case let .overtime(since) = phase {
            max(0, now.timeIntervalSince(since))
        } else {
            0
        }
    }

    /// Running time plus overtime, without paused time. This is what the session records.
    func activeSeconds(at now: Date) -> TimeInterval {
        accumulatedActiveSeconds + (lastResumedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// When the timer gets (or got) to zero. While paused, this is when it would end if it resumed now.
    func endDate(at now: Date) -> Date {
        switch phase {
        case let .running(endDate): endDate
        case let .paused(remaining): now.addingTimeInterval(remaining)
        case let .overtime(since): since
        }
    }
}
