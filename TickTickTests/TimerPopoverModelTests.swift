// Last edited: 2026-09-24 15:42 PT

import Foundation
import Testing
@testable import TickTick

struct TimerPopoverModelTests {
    /// en_US puts this narrow no-break space (U+202F) between the time and `AM` or `PM`.
    private let narrowSpace = "\u{202F}"
    private let locale = Locale(identifier: "en_US")
    private let timeZone: TimeZone
    /// 3:00 PM in Los Angeles on Thursday 24 September 2026. Every timer here starts at this time.
    private let start: Date

    init() throws {
        timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        start = try Date("2026-09-24T15:00:00-07:00", strategy: .iso8601)
    }

    @Test("Running: time left, progress, start and end, estimate and day")
    func running() {
        let timer = timer(planned: 1500, phase: .running(endDate: start + 1500))

        let model = model(timer, estimate: 1500, now: start + 600)

        #expect(model.phase == .running)
        #expect(model.caption == "Time left")
        #expect(model.timeText == "15:00")
        #expect(model.progress == 0.4)
        #expect(model.percentText == "40%")
        #expect(model.scheduleText == "Started 3:00\(narrowSpace)PM · Ends 3:25\(narrowSpace)PM")
        #expect(model.estimateText == "Estimate 25 min · Thu 24 Sep")
        #expect(model.taskTitle == "Write cover letter")
        #expect(model.noteTitle == "Inbox")
    }

    @Test("Paused: the end is now plus the time left, so it moves while the timer waits")
    func paused() {
        let timer = timer(planned: 1500, phase: .paused(remaining: 300))

        let model = model(timer, estimate: 1500, now: start + 1800)

        #expect(model.phase == .paused)
        #expect(model.caption == "Paused")
        #expect(model.timeText == "5:00")
        #expect(model.progress == 0.8)
        #expect(model.scheduleText == "Started 3:00\(narrowSpace)PM · Ends 3:35\(narrowSpace)PM")
    }

    @Test("Overtime: the time counts up, the bar is full, and the end is in the past")
    func overtime() {
        let timer = timer(planned: 1500, phase: .overtime(since: start + 1500))

        let model = model(timer, estimate: 1500, now: start + 1633)

        #expect(model.phase == .overtime)
        #expect(model.caption == "Over time")
        #expect(model.timeText == "+2:13")
        #expect(model.progress == 1)
        #expect(model.percentText == "100%")
        #expect(model.scheduleText == "Started 3:00\(narrowSpace)PM · Ended 3:25\(narrowSpace)PM")
    }

    @Test("An extension grows the planned time, so the progress drops")
    func extensionLowersTheProgress() {
        // 25 min + 5 min, 15 min in.
        let timer = timer(planned: 1800, phase: .running(endDate: start + 1800))

        let model = model(timer, estimate: 1500, now: start + 900)

        #expect(model.progress == 0.5)
        #expect(model.percentText == "50%")
        #expect(model.timeText == "15:00")
    }

    @Test("The percent rounds down, so it shows 100% only at the end")
    func percentRoundsDown() {
        let timer = timer(planned: 1000, phase: .running(endDate: start + 1000))

        #expect(model(timer, estimate: nil, now: start + 999).percentText == "99%")
        #expect(model(timer, estimate: nil, now: start).percentText == "0%")
    }

    @Test("A task with no estimate shows only the day")
    func noEstimate() {
        let timer = timer(planned: 1500, phase: .running(endDate: start + 1500))

        #expect(model(timer, estimate: nil, now: start).estimateText == "Thu 24 Sep")
    }

    @Test("A planned time of 0 gives no progress and does not divide by zero")
    func zeroPlannedTime() {
        let timer = timer(planned: 0, phase: .paused(remaining: 0))

        #expect(model(timer, estimate: nil, now: start).progress == 0)
    }

    // MARK: - Helpers

    private func timer(planned: TimeInterval, phase: ActiveTimer.Phase) -> ActiveTimer {
        ActiveTimer(
            taskID: UUID(),
            sessionID: UUID(),
            plannedSeconds: planned,
            startedAt: start,
            accumulatedActiveSeconds: 0,
            lastResumedAt: start,
            phase: phase
        )
    }

    private func model(_ timer: ActiveTimer, estimate: TimeInterval?, now: Date) -> TimerPopoverModel {
        TimerPopoverModel(
            timer: timer,
            taskTitle: "Write cover letter",
            noteTitle: "Inbox",
            estimateSeconds: estimate,
            now: now,
            locale: locale,
            timeZone: timeZone
        )
    }
}
