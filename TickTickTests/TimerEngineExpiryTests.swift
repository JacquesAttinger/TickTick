// Last edited: 2026-09-24 15:16 PT

import AppKit
import Foundation
import Testing
@testable import TickTick

/// Expiry, overtime, extend, and the active time rules of `TimerEngine`.
@MainActor
struct TimerEngineExpiryTests {
    private let clock: TestClock
    private let service: TaskService
    private let engine: TimerEngine
    private let task: TaskItem
    private let store: ModelStore

    init() throws {
        let clock = TestClock()
        self.clock = clock
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        task = try service.createTask(title: "Write report", in: store.bootstrapInbox())
    }

    // MARK: - Expiry

    @Test("checkExpiry before the end does nothing")
    func checkExpiryBeforeTheEndDoesNothing() {
        var expired = 0
        engine.onExpired = { _ in expired += 1 }
        engine.start(task: task, seconds: 60)
        let running = engine.state
        clock.advance(by: 59)

        engine.checkExpiry()

        #expect(engine.state == running)
        #expect(expired == 0)
    }

    @Test("Expired fires exactly once, even when checkExpiry runs again")
    func expiredFiresExactlyOnce() throws {
        var expired: [ActiveTimer] = []
        engine.onExpired = { expired.append($0) }
        engine.start(task: task, seconds: 60)
        let end = clock.now.addingTimeInterval(60)
        clock.advance(by: 60)

        engine.checkExpiry()
        engine.checkExpiry()
        clock.advance(by: 30)
        engine.checkExpiry()

        #expect(expired.count == 1)
        #expect(expired.first?.phase == .overtime(since: end))
        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .overtime(since: end))
        #expect(timer.overtime(at: clock.now) == 30)
    }

    @Test("Expiry during sleep fires once on wake, with the overtime counted from the old end")
    func expiryDuringSleepFiresOnce() throws {
        var expired = 0
        engine.onExpired = { _ in expired += 1 }
        engine.start(task: task, seconds: 120)
        clock.advance(by: 180)

        engine.checkExpiry()
        engine.checkExpiry()

        #expect(expired == 1)
        #expect(try #require(engine.activeTimer).overtime(at: clock.now) == 60)
    }

    @Test("An operation after the end first moves the timer to overtime")
    func operationsCheckExpiryFirst() throws {
        var expired = 0
        engine.onExpired = { _ in expired += 1 }
        engine.start(task: task, seconds: 60)
        clock.advance(by: 70)

        engine.pause()

        #expect(expired == 1)
        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .overtime(since: timer.startedAt.addingTimeInterval(60)))
    }

    // MARK: - Extend

    @Test("Extend while running moves the end date and grows the planned time")
    func extendWhileRunning() throws {
        engine.start(task: task, seconds: 60)
        let end = clock.now.addingTimeInterval(60)
        clock.advance(by: 20)

        engine.extend(seconds: 300)

        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .running(endDate: end.addingTimeInterval(300)))
        #expect(timer.plannedSeconds == 360)
        #expect(timer.activeSeconds(at: clock.now) + timer.remaining(at: clock.now) == 360)
    }

    @Test("Extend while paused adds to the remaining time")
    func extendWhilePaused() throws {
        engine.start(task: task, seconds: 60)
        clock.advance(by: 20)
        engine.pause()

        engine.extend(seconds: 60)

        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .paused(remaining: 100))
        #expect(timer.plannedSeconds == 120)
    }

    @Test("Extend in overtime goes back to running, and the timer can expire again")
    func extendInOvertimeGoesBackToRunning() throws {
        var expired = 0
        engine.onExpired = { _ in expired += 1 }
        engine.start(task: task, seconds: 60)
        clock.advance(by: 90)
        engine.checkExpiry()

        engine.extend(seconds: 300)

        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .running(endDate: clock.now.addingTimeInterval(300)))
        #expect(timer.activeSeconds(at: clock.now) == 90)
        #expect(timer.plannedSeconds == 390)

        clock.advance(by: 300)
        engine.checkExpiry()
        #expect(expired == 2)
    }

    @Test("Extend by zero or less, or while idle, does nothing")
    func extendIgnoresBadInput() {
        engine.extend(seconds: 60)
        #expect(engine.state == .idle)

        engine.start(task: task, seconds: 60)
        let running = engine.state
        engine.extend(seconds: 0)
        engine.extend(seconds: -30)
        #expect(engine.state == running)
    }

    // MARK: - Active time

    @Test("activeSeconds does not count pauses")
    func activeSecondsDoesNotCountPauses() throws {
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 60)
        engine.pause()
        clock.advance(by: 30)
        engine.resume()
        clock.advance(by: 60)

        engine.stop()

        #expect(service.session(withID: sessionID)?.activeSeconds == 120)
        #expect(service.actualSeconds(for: task) == 120)
    }

    @Test("activeSeconds counts overtime")
    func activeSecondsCountsOvertime() throws {
        engine.start(task: task, seconds: 60)
        let sessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 90)
        engine.checkExpiry()

        engine.done()

        let session = try #require(service.session(withID: sessionID))
        #expect(session.activeSeconds == 90)
        #expect(session.outcome == .done)
    }

    // MARK: - Scheduling in the app

    @Test("With schedulesExpiry, a wall-clock Timer moves the timer to overtime at the end")
    func scheduledTimerFiresAtTheEnd() async throws {
        let engine = TimerEngine(service: service, clock: SystemClock(), schedulesExpiry: true)
        var expired = 0
        engine.onExpired = { _ in expired += 1 }

        engine.start(task: task, seconds: 0.2)
        for _ in 0 ..< 40 where expired == 0 {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(expired == 1)
        #expect(engine.activeTimer?.overtime(at: .now) ?? 0 > 0)
        engine.stop()
    }

    @Test("With schedulesExpiry, a wake from sleep checks the end again")
    func wakeChecksExpiry() {
        // Real time, so the armed wall-clock Timer is far in the future and cannot fire during the test.
        clock.now = .now
        let engine = TimerEngine(service: service, clock: clock, schedulesExpiry: true)
        var expired = 0
        engine.onExpired = { _ in expired += 1 }
        engine.start(task: task, seconds: 120)
        clock.advance(by: 180)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)

        #expect(expired == 1)
        engine.stop()
    }
}
