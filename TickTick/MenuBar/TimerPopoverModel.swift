// Last edited: 2026-09-24 15:42 PT

import Foundation

/// The text and numbers that the popover shows for an active timer (decision 10).
/// It is pure, so tests can check it with a fixed time, locale, and time zone.
struct TimerPopoverModel: Equatable {
    enum Phase: Equatable {
        case running, paused, overtime
    }

    let phase: Phase
    let taskTitle: String
    let noteTitle: String
    /// A word above the big time: `Time left`, `Paused`, or `Over time`.
    let caption: String
    /// The time left (`24:13`), or the time past zero (`+2:13`).
    let timeText: String
    /// Elapsed time over the planned time with every extension, from 0 to 1. It is 1 in overtime.
    let progress: Double
    /// The progress in whole percent, rounded down: `40%`.
    let percentText: String
    /// `Started 3:00 PM · Ends 3:25 PM`. Paused, the end is when the timer would end if it resumed now.
    /// In overtime it says `Ended`.
    let scheduleText: String
    /// `Estimate 25 min · Thu 24 Sep`, or only the day when the task has no estimate. The day is the start day.
    let estimateText: String

    init(
        timer: ActiveTimer,
        taskTitle: String,
        noteTitle: String,
        estimateSeconds: TimeInterval?,
        now: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        self.taskTitle = taskTitle
        self.noteTitle = noteTitle
        switch timer.phase {
        case .running:
            phase = .running
            caption = "Time left"
            timeText = TimeFormatting.countdown(timer.remaining(at: now))
        case .paused:
            phase = .paused
            caption = "Paused"
            timeText = TimeFormatting.countdown(timer.remaining(at: now))
        case .overtime:
            phase = .overtime
            caption = "Over time"
            timeText = TimeFormatting.overtime(timer.overtime(at: now))
        }
        progress = Self.progress(of: timer, at: now)
        percentText = "\(Int((progress * 100).rounded(.down)))%"

        let started = TimeFormatting.clock(timer.startedAt, locale: locale, timeZone: timeZone)
        let end = TimeFormatting.clock(timer.endDate(at: now), locale: locale, timeZone: timeZone)
        let endWord = phase == .overtime ? "Ended" : "Ends"
        scheduleText = "Started \(started) · \(endWord) \(end)"

        let day = TimeFormatting.day(timer.startedAt, locale: locale, timeZone: timeZone)
        estimateText = estimateSeconds.map { "Estimate \(TimeFormatting.human($0)) · \(day)" } ?? day
    }

    private static func progress(of timer: ActiveTimer, at now: Date) -> Double {
        if case .overtime = timer.phase {
            return 1
        }
        guard timer.plannedSeconds > 0 else {
            return 0
        }
        let elapsed = timer.plannedSeconds - timer.remaining(at: now)
        return min(1, max(0, elapsed / timer.plannedSeconds))
    }
}
