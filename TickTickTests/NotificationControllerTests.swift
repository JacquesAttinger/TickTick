// Last edited: 2026-09-24 17:02 PT

import Foundation
import Testing
@testable import TickTick
import UserNotifications

/// `NotificationController` against a fake center: the category, the schedule and cancel flows, the expiry check,
/// and the banner buttons.
@MainActor
struct NotificationControllerTests {
    private let clock = TestClock()
    private let center = FakeNotificationCenter()
    private let store: ModelStore
    private let engine: TimerEngine
    private let controller: NotificationController
    private let task: TaskItem

    init() throws {
        let clock = clock
        store = try ModelStore(inMemory: true)
        let service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        controller = NotificationController(center: center, engine: engine, deliveryCheckDelay: .zero)
        task = try service.createTask(title: "Write report", in: store.bootstrapInbox())
    }

    private var content: NotificationContent {
        .make(taskName: "Write report", plannedSeconds: 600)
    }

    private func schedule(id: String = "A", in seconds: TimeInterval = 600) -> NotificationDecision {
        .schedule(id: id, fireDate: clock.now.addingTimeInterval(seconds), content: content)
    }

    // MARK: - Start

    @Test("start registers TIMER_DONE with Done, +5 min, and Stop, becomes the delegate, and asks for permission")
    func startRegistersTheCategory() async throws {
        controller.start()
        try await Task.sleep(for: .milliseconds(10))

        let category = try #require(center.categories.first)
        #expect(center.categories.count == 1)
        #expect(category.identifier == "TIMER_DONE")
        #expect(category.actions.map(\.title) == ["Done", "+5 min", "Stop"])
        #expect(center.delegate === controller)
        #expect(center.authorizationRequests == [[.alert, .sound]])
    }

    // MARK: - Schedule and cancel

    @Test("A schedule adds a silent, active request that fires when the time is up")
    func scheduleAddsARequest() throws {
        controller.apply(schedule(in: 600))

        let request = try #require(center.pending.first)
        #expect(center.pending.count == 1)
        #expect(request.identifier == "A")
        #expect(request.content.title == "Time's up: Write report")
        #expect(request.content.body == "Estimate was 10 min")
        #expect(request.content.categoryIdentifier == "TIMER_DONE")
        #expect(request.content.interruptionLevel == .active)
        #expect(request.content.sound == nil)
        let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 600)
        #expect(!trigger.repeats)
    }

    @Test("Schedule then cancel leaves nothing scheduled or shown")
    func scheduleThenCancelLeavesNothing() {
        controller.apply(schedule())
        controller.apply(.cancel)

        #expect(center.pending.isEmpty)
        #expect(center.delivered.isEmpty)
    }

    @Test("A new schedule for the same session replaces the old request")
    func rescheduleReplacesTheRequest() throws {
        controller.apply(schedule(in: 600))
        clock.advance(by: 100)
        controller.apply(schedule(in: 800))

        #expect(center.pending.map(\.identifier) == ["A"])
        let trigger = try #require(center.pending.first?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval == 800)
    }

    @Test("The same decision twice adds one request")
    func sameDecisionTwiceAddsOnce() {
        let decision = schedule()
        controller.apply(decision)
        controller.apply(decision)
        controller.apply(.keep)

        #expect(center.added.count == 1)
    }

    @Test("A schedule removes the scheduled banner of another session, and a shown old banner")
    func scheduleRemovesOtherSessions() async {
        controller.apply(schedule(id: "A"))
        center.fire("A")
        center.addRequest(NotificationController.makeRequest(
            id: "left from before",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        ))

        await controller.apply(schedule(id: "B"))?.value

        #expect(center.pending.map(\.identifier) == ["B"])
        #expect(center.delivered.isEmpty)
    }

    @Test("A schedule for a time that just passed still uses a trigger above 0")
    func scheduleInThePastUsesAPositiveTrigger() throws {
        controller.apply(schedule(in: -1))

        let trigger = try #require(center.pending.first?.trigger as? UNTimeIntervalNotificationTrigger)
        #expect(trigger.timeInterval > 0)
    }

    // MARK: - Expiry check

    @Test("The expiry check adds nothing when the system already showed the banner")
    func ensureDeliveredSkipsADeliveredBanner() async throws {
        let timer = try startTimer()
        center.fire(NotificationPlanner.identifier(for: timer))

        await controller.ensureDelivered(for: timer, taskName: "Write report")

        #expect(center.added.count == 1)
        #expect(center.delivered.count == 1)
    }

    @Test("The expiry check adds nothing when the banner is still scheduled")
    func ensureDeliveredSkipsAPendingBanner() async throws {
        let timer = try startTimer()

        await controller.ensureDelivered(for: timer, taskName: "Write report")

        #expect(center.added.count == 1)
    }

    @Test("The expiry check shows the banner at once when the system has none")
    func ensureDeliveredShowsAMissingBanner() async throws {
        let timer = try startTimer()
        center.removeAllRequests()

        await controller.ensureDelivered(for: timer, taskName: "Write report")

        let request = try #require(center.delivered.first)
        #expect(center.delivered.count == 1)
        #expect(request.identifier == NotificationPlanner.identifier(for: timer))
        #expect(request.trigger == nil)
        #expect(request.content.title == "Time's up: Write report")
    }

    @Test("The expiry check stops when the timer changes while it waits")
    func ensureDeliveredStopsAfterAChange() async throws {
        let timer = try startTimer()
        center.removeAllRequests()
        center.beforeQuery = { [controller] in controller.apply(.cancel) }

        await controller.ensureDelivered(for: timer, taskName: "Write report")

        #expect(center.delivered.isEmpty)
        #expect(center.added.count == 1)
    }

    /// Starts a 10 min timer and schedules its banner, as `AlarmController` does.
    private func startTimer() throws -> ActiveTimer {
        engine.start(task: task, seconds: 600)
        let timer = try #require(engine.activeTimer)
        controller.apply(NotificationPlanner.plan(for: engine.state, taskName: task.title, now: clock.now))
        return timer
    }
}
