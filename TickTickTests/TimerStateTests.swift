// Last edited: 2026-09-24 15:09 PT

import Foundation
import Testing
@testable import TickTick

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func makeTimer(_ phase: ActiveTimer.Phase, lastResumedAt: Date? = start) -> ActiveTimer {
    ActiveTimer(
        taskID: UUID(),
        sessionID: UUID(),
        plannedSeconds: 1500,
        startedAt: start,
        accumulatedActiveSeconds: 30.5,
        lastResumedAt: lastResumedAt,
        phase: phase
    )
}

struct TimerStateTests {
    @Test(
        "Every state survives a JSON round trip",
        arguments: [
            TimerState.idle,
            .active(makeTimer(.running(endDate: start.addingTimeInterval(1500.25)))),
            .active(makeTimer(.paused(remaining: 612.75), lastResumedAt: nil)),
            .active(makeTimer(.overtime(since: start.addingTimeInterval(1500)))),
        ]
    )
    func stateRoundTripsThroughJSON(state: TimerState) throws {
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TimerState.self, from: data)

        #expect(decoded == state)
    }

    @Test("activeTimer is nil only when idle")
    func activeTimerMatchesTheCase() {
        let timer = makeTimer(.paused(remaining: 10), lastResumedAt: nil)

        #expect(TimerState.idle.activeTimer == nil)
        #expect(TimerState.active(timer).activeTimer == timer)
    }

    @Test("A running timer counts down to its end date and counts active time since the last resume")
    func runningTimerValues() {
        let end = start.addingTimeInterval(100)
        let timer = makeTimer(.running(endDate: end))
        let now = start.addingTimeInterval(40)

        #expect(timer.remaining(at: now) == 60)
        #expect(timer.overtime(at: now) == 0)
        #expect(timer.activeSeconds(at: now) == 70.5)
        #expect(timer.endDate(at: now) == end)
        #expect(timer.remaining(at: end.addingTimeInterval(5)) == 0)
    }

    @Test("A paused timer keeps its remaining time and does not count active time")
    func pausedTimerValues() {
        let timer = makeTimer(.paused(remaining: 90), lastResumedAt: nil)
        let now = start.addingTimeInterval(1000)

        #expect(timer.remaining(at: now) == 90)
        #expect(timer.overtime(at: now) == 0)
        #expect(timer.activeSeconds(at: now) == 30.5)
        #expect(timer.endDate(at: now) == now.addingTimeInterval(90))
    }

    @Test("An overtime timer counts up from its old end date and keeps counting active time")
    func overtimeTimerValues() {
        let since = start.addingTimeInterval(100)
        let timer = makeTimer(.overtime(since: since))
        let now = since.addingTimeInterval(25)

        #expect(timer.remaining(at: now) == 0)
        #expect(timer.overtime(at: now) == 25)
        #expect(timer.activeSeconds(at: now) == 155.5)
        #expect(timer.endDate(at: now) == since)
    }
}
