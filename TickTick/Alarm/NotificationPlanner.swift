// Last edited: 2026-09-24 16:52 PT

import Foundation

/// The text of the "time is up" notification.
struct NotificationContent: Equatable {
    let title: String
    let body: String

    /// `Time's up: Write cover letter` and `Estimate was 45 min`.
    /// `plannedSeconds` is the timer's planned time, with every extension.
    static func make(taskName: String, plannedSeconds: TimeInterval) -> NotificationContent {
        NotificationContent(
            title: "Time's up: \(taskName)",
            body: "Estimate was \(TimeFormatting.human(plannedSeconds))"
        )
    }
}

/// What to do with the scheduled notification after a timer change.
enum NotificationDecision: Equatable {
    /// Schedule the notification for `fireDate`. The ID is the timer session's UUID, so a new schedule for the
    /// same session replaces the old one.
    case schedule(id: String, fireDate: Date, content: NotificationContent)
    /// Remove every scheduled and shown notification. No timer counts down.
    case cancel
    /// Change nothing. In overtime, the notification fired already, or the expiry check makes sure it shows.
    case keep
}

/// Maps the timer state to a `NotificationDecision`. Pure values only, so tests need no notification center.
enum NotificationPlanner {
    /// - Running: schedule for the end date. When the end date has passed, keep: the engine moves the timer to
    ///   overtime soon, and its expiry check handles the notification.
    /// - Paused: cancel. A paused timer has no end date, so it must never show the banner.
    /// - Overtime: keep.
    /// - Idle (after stop and done too): cancel.
    static func plan(for state: TimerState, taskName: String, now: Date) -> NotificationDecision {
        guard let timer = state.activeTimer else {
            return .cancel
        }
        switch timer.phase {
        case let .running(endDate):
            guard endDate > now else {
                return .keep
            }
            return .schedule(
                id: identifier(for: timer),
                fireDate: endDate,
                content: .make(taskName: taskName, plannedSeconds: timer.plannedSeconds)
            )
        case .paused:
            return .cancel
        case .overtime:
            return .keep
        }
    }

    /// The notification ID of a timer: its session's UUID. A notification action uses it to check that it
    /// still belongs to the active timer.
    static func identifier(for timer: ActiveTimer) -> String {
        timer.sessionID.uuidString
    }
}
