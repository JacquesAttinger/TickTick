// Last edited: 2026-09-24 16:52 PT

import Foundation
import Testing
@testable import TickTick

/// The notification text, and the notification decision for each timer state.
struct NotificationPlannerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let sessionID = UUID()

    private func timer(_ phase: ActiveTimer.Phase, plannedSeconds: TimeInterval = 2700) -> TimerState {
        .active(ActiveTimer(
            taskID: UUID(),
            sessionID: sessionID,
            plannedSeconds: plannedSeconds,
            startedAt: now.addingTimeInterval(-600),
            accumulatedActiveSeconds: 0,
            lastResumedAt: now.addingTimeInterval(-600),
            phase: phase
        ))
    }

    // MARK: - Content

    @Test("The title names the task, and the body gives the estimate")
    func contentNamesTheTaskAndTheEstimate() {
        let content = NotificationContent.make(taskName: "Write cover letter", plannedSeconds: 2700)

        #expect(content.title == "Time's up: Write cover letter")
        #expect(content.body == "Estimate was 45 min")
    }

    @Test("The body shows hours, and at least 1 min")
    func contentUsesTheHumanDuration() {
        #expect(NotificationContent.make(taskName: "A", plannedSeconds: 5400).body == "Estimate was 1 h 30 min")
        #expect(NotificationContent.make(taskName: "A", plannedSeconds: 10).body == "Estimate was 1 min")
    }

    // MARK: - Decisions

    @Test("Running schedules the notification for the end date, with the session ID")
    func runningSchedules() {
        let end = now.addingTimeInterval(300)

        let decision = NotificationPlanner.plan(for: timer(.running(endDate: end)), taskName: "Write", now: now)

        #expect(decision == .schedule(
            id: sessionID.uuidString,
            fireDate: end,
            content: NotificationContent(title: "Time's up: Write", body: "Estimate was 45 min")
        ))
    }

    @Test("Running at or past the end date keeps, because the expiry check handles it", arguments: [0.0, -5.0])
    func runningPastTheEndKeeps(offset: TimeInterval) {
        let state = timer(.running(endDate: now.addingTimeInterval(offset)))

        #expect(NotificationPlanner.plan(for: state, taskName: "Write", now: now) == .keep)
    }

    @Test("Paused cancels, so a paused timer never shows the banner")
    func pausedCancels() {
        #expect(NotificationPlanner.plan(for: timer(.paused(remaining: 120)), taskName: "Write", now: now) == .cancel)
    }

    @Test("Overtime keeps")
    func overtimeKeeps() {
        let state = timer(.overtime(since: now.addingTimeInterval(-30)))

        #expect(NotificationPlanner.plan(for: state, taskName: "Write", now: now) == .keep)
    }

    @Test("Idle cancels")
    func idleCancels() {
        #expect(NotificationPlanner.plan(for: .idle, taskName: "", now: now) == .cancel)
    }

    @Test("A new task name or an extension gives a new schedule for the same ID")
    func changesGiveANewSchedule() {
        let end = now.addingTimeInterval(300)
        let first = NotificationPlanner.plan(for: timer(.running(endDate: end)), taskName: "Write", now: now)
        let renamed = NotificationPlanner.plan(for: timer(.running(endDate: end)), taskName: "Edit", now: now)
        let extended = NotificationPlanner.plan(
            for: timer(.running(endDate: end.addingTimeInterval(300)), plannedSeconds: 3000),
            taskName: "Write",
            now: now
        )

        #expect(first != renamed)
        #expect(first != extended)
        #expect(extended == .schedule(
            id: sessionID.uuidString,
            fireDate: end.addingTimeInterval(300),
            content: NotificationContent(title: "Time's up: Write", body: "Estimate was 50 min")
        ))
    }
}
