// Last edited: 2026-09-24 16:56 PT

import Foundation
import Testing
@testable import TickTick

/// `AlarmController` with a real engine and a fake notification center: the alarm fires once at zero, and the
/// banner follows every timer change. The flash and the sound are a counter here.
@MainActor
struct AlarmControllerTests {
    private let clock = TestClock()
    private let center = FakeNotificationCenter()
    private let store: ModelStore
    private let service: TaskService
    private let task: TaskItem

    init() throws {
        let clock = clock
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: { clock.now })
        task = try service.createTask(title: "Write report", in: store.bootstrapInbox())
    }

    /// An engine with an alarm, as the app builds them at launch. `signals` counts the flash-and-sound calls.
    private final class Launch {
        let engine: TimerEngine
        let alarm: AlarmController
        var signals = 0

        @MainActor
        init(service: TaskService, clock: TestClock, center: FakeNotificationCenter) {
            engine = TimerEngine(service: service, clock: clock)
            let notifications = NotificationController(center: center, engine: engine, deliveryCheckDelay: .zero)
            var signal: (() -> Void)?
            alarm = AlarmController(engine: engine, notifications: notifications) { signal?() }
            signal = { [unowned self] in signals += 1 }
        }
    }

    private func launch() -> Launch {
        Launch(service: service, clock: clock, center: center)
    }

    /// Lets the observation run again after a timer change. It waits for the next main actor turn.
    private func settle() async {
        for _ in 0 ..< 3 {
            await Task.yield()
        }
    }

    @Test("Every timer change schedules or cancels the banner")
    func timerChangesScheduleAndCancel() async {
        let app = launch()
        app.alarm.startSyncingNotifications()
        let id = { app.engine.activeTimer.map(NotificationPlanner.identifier(for:)) }

        app.engine.start(task: task, seconds: 600)
        await settle()
        #expect(center.pending.map(\.identifier) == [id()])

        app.engine.pause()
        await settle()
        #expect(center.pending.isEmpty)

        app.engine.resume()
        await settle()
        #expect(center.pending.map(\.identifier) == [id()])

        app.engine.stop()
        await settle()
        #expect(center.pending.isEmpty)
    }

    @Test("A rename of the running task gives the banner the new name")
    func renameReschedules() async throws {
        let app = launch()
        app.alarm.startSyncingNotifications()
        app.engine.start(task: task, seconds: 600)
        await settle()

        task.title = "Write the report"
        await settle()

        let request = try #require(center.pending.first)
        #expect(center.pending.count == 1)
        #expect(request.content.title == "Time's up: Write the report")
    }

    @Test("At zero the alarm fires once, and the banner that the system showed is not added again")
    func alarmFiresOnceAtZero() async throws {
        let app = launch()
        app.alarm.startSyncingNotifications()
        app.engine.start(task: task, seconds: 60)
        await settle()
        let id = try NotificationPlanner.identifier(for: #require(app.engine.activeTimer))

        clock.advance(by: 60)
        center.fire(id)
        app.engine.checkExpiry()
        await app.alarm.deliveryCheck?.value
        app.engine.checkExpiry()
        await settle()

        #expect(app.signals == 1)
        #expect(center.added.count == 1)
        #expect(center.delivered.map(\.identifier) == [id])
    }

    @Test("A relaunch in overtime fires no alarm and keeps the shown banner")
    func relaunchInOvertimeIsQuiet() async throws {
        let first = launch()
        first.alarm.startSyncingNotifications()
        first.engine.start(task: task, seconds: 60)
        await settle()
        clock.advance(by: 60)
        try center.fire(NotificationPlanner.identifier(for: #require(first.engine.activeTimer)))
        first.engine.checkExpiry()
        await first.alarm.deliveryCheck?.value
        let saved = first.engine.state
        #expect(first.signals == 1)

        clock.advance(by: 30)
        let second = launch()
        second.engine.restore(saved)
        second.alarm.startSyncingNotifications()
        await settle()

        #expect(second.signals == 0)
        #expect(second.alarm.deliveryCheck == nil)
        #expect(center.delivered.count == 1)
    }

    @Test("A relaunch after the end passed while quit fires the alarm once, without a second banner")
    func relaunchPastTheEndFiresOnce() async throws {
        let first = launch()
        first.alarm.startSyncingNotifications()
        first.engine.start(task: task, seconds: 60)
        await settle()
        let saved = first.engine.state
        let id = try NotificationPlanner.identifier(for: #require(saved.activeTimer))

        // The app is quit. The system shows the scheduled banner at the end.
        clock.advance(by: 90)
        center.fire(id)
        let second = launch()
        second.engine.restore(saved)
        second.alarm.startSyncingNotifications()
        await second.alarm.deliveryCheck?.value
        await settle()

        #expect(second.signals == 1)
        #expect(center.added.count == 1)
        #expect(center.delivered.map(\.identifier) == [id])
    }
}
