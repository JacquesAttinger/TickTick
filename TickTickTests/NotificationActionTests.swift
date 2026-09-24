// Last edited: 2026-09-24 17:02 PT

import Foundation
import Testing
@testable import TickTick

/// The banner buttons Done, +5 min, and Stop, and the guard against a banner of an older timer.
@MainActor
struct NotificationActionTests {
    private let clock = TestClock()
    private let store: ModelStore
    private let engine: TimerEngine
    private let controller: NotificationController
    private let task: TaskItem
    private let timer: ActiveTimer

    /// Starts a 10 min timer and lets it run 30 s into overtime, as when the banner shows.
    init() throws {
        let clock = clock
        store = try ModelStore(inMemory: true)
        let service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        controller = NotificationController(center: FakeNotificationCenter(), engine: engine, deliveryCheckDelay: .zero)
        task = try service.createTask(title: "Write report", in: store.bootstrapInbox())
        engine.start(task: task, seconds: 600)
        clock.advance(by: 630)
        engine.checkExpiry()
        timer = try #require(engine.activeTimer)
    }

    private var id: String {
        NotificationPlanner.identifier(for: timer)
    }

    @Test("Done ends the timer and checks the task")
    func doneEndsTheTimerAndChecksTheTask() {
        #expect(controller.handleAction("DONE", notificationID: id))

        #expect(engine.state == .idle)
        #expect(task.isDone)
    }

    @Test("+5 min runs the timer again with 5 min left")
    func extendRunsTheTimerForFiveMinutes() throws {
        #expect(controller.handleAction("EXTEND_5_MIN", notificationID: id))

        let running = try #require(engine.activeTimer)
        #expect(running.sessionID == timer.sessionID)
        #expect(running.phase == .running(endDate: clock.now.addingTimeInterval(300)))
    }

    @Test("Stop ends the timer and keeps the task open")
    func stopEndsTheTimerAndKeepsTheTask() {
        #expect(controller.handleAction("STOP", notificationID: id))

        #expect(engine.state == .idle)
        #expect(!task.isDone)
    }

    @Test("A button of an older timer's banner does nothing")
    func staleBannerDoesNothing() {
        let before = engine.state

        #expect(!controller.handleAction("DONE", notificationID: UUID().uuidString))
        #expect(!controller.handleAction("EXTEND_5_MIN", notificationID: UUID().uuidString))

        #expect(engine.state == before)
        #expect(!task.isDone)
    }

    @Test("A button after the timer ended does nothing")
    func buttonAfterTheTimerEndedDoesNothing() {
        engine.stop()

        #expect(!controller.handleAction("EXTEND_5_MIN", notificationID: id))
        #expect(engine.state == .idle)
    }

    @Test("A click on the banner itself does not change the timer")
    func bannerClickDoesNothing() {
        let before = engine.state

        #expect(!controller.handleAction("com.apple.UNNotificationDefaultActionIdentifier", notificationID: id))

        #expect(engine.state == before)
    }
}
