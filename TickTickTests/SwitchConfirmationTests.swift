// Last edited: 2026-09-24 17:58 PT

import Foundation
import Testing
@testable import TickTick

struct SwitchConfirmationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func timer(_ phase: ActiveTimer.Phase) -> ActiveTimer {
        ActiveTimer(
            taskID: UUID(),
            sessionID: UUID(),
            plannedSeconds: 1500,
            startedAt: start,
            accumulatedActiveSeconds: 0,
            lastResumedAt: start,
            phase: phase
        )
    }

    @Test("Running: the question names both tasks and the minutes left")
    func running() {
        let message = SwitchConfirmation.message(
            current: timer(.running(endDate: start + 1500)),
            currentTitle: "A",
            newTitle: "B",
            now: start + 780
        )

        #expect(message == "Stop “A” (12 min left) and start “B”?")
    }

    @Test("Paused: the minutes left are the paused time left")
    func paused() {
        #expect(SwitchConfirmation.timeText(timer(.paused(remaining: 300)), now: start + 9999) == "5 min left")
    }

    @Test("Overtime: it says how long it is over, not 0 min left")
    func overtime() {
        let overtime = timer(.overtime(since: start + 1500))

        #expect(SwitchConfirmation.timeText(overtime, now: start + 1620) == "2 min over")
    }
}
