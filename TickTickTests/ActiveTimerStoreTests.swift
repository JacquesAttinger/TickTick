// Last edited: 2026-09-24 15:18 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// Saving the timer state and restoring it after a quit. Each "relaunch" builds a new engine and store
/// on the same data and the same defaults key.
///
/// All tests share one defaults suite (one plist file in `~/Library/Preferences`), and each test uses its own key.
@MainActor
final class ActiveTimerStoreTests {
    private nonisolated static let suiteName = "com.jacquesattinger.TickTickTests"
    private let key = "activeTimer.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let clock: TestClock
    private let store: ModelStore
    private let service: TaskService
    private let task: TaskItem
    private var expired: [ActiveTimer] = []

    init() throws {
        let clock = TestClock()
        self.clock = clock
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: { clock.now })
        task = try service.createTask(title: "Write report", in: store.bootstrapInbox())
    }

    deinit {
        UserDefaults(suiteName: Self.suiteName)?.removeObject(forKey: key)
    }

    // MARK: - Save and load

    @Test("save writes readable JSON, and load reads it back")
    func saveAndLoadRoundTrip() throws {
        let engine = launch()
        engine.start(task: task, seconds: 1500)

        let json = try #require(defaults.string(forKey: key))
        #expect(json.contains("running"))
        #expect(json.contains(task.id.uuidString))
        #expect(makeStore().load() == engine.state)
    }

    @Test("Going idle removes the saved state")
    func idleRemovesTheKey() {
        let engine = launch()
        engine.start(task: task, seconds: 1500)

        engine.stop()

        #expect(defaults.object(forKey: key) == nil)
        #expect(makeStore().load() == .idle)
    }

    @Test("Unreadable saved text loads as idle and is dropped")
    func unreadableTextLoadsAsIdle() {
        defaults.set("{not json", forKey: key)

        #expect(makeStore().load() == .idle)
        #expect(defaults.object(forKey: key) == nil)
    }

    // MARK: - Restore after quit

    @Test("Restore after quit before the end keeps the timer running")
    func restoreBeforeTheEnd() throws {
        let first = launch()
        first.start(task: task, seconds: 1500)
        let saved = first.state
        clock.advance(by: 600)

        let second = launch()

        #expect(second.state == saved)
        #expect(try #require(second.activeTimer).remaining(at: clock.now) == 900)
        #expect(second.activeTask === task)
        #expect(expired.isEmpty)
    }

    @Test("Restore after quit past the end goes to overtime and fires expired once")
    func restoreAfterTheEnd() throws {
        let first = launch()
        first.start(task: task, seconds: 60)
        let end = clock.now.addingTimeInterval(60)
        clock.advance(by: 90)

        let second = launch()
        second.checkExpiry()

        #expect(second.activeTimer?.phase == .overtime(since: end))
        #expect(expired.count == 1)
        #expect(makeStore().load() == second.state)

        clock.advance(by: 30)
        let third = launch()

        #expect(third.activeTimer?.phase == .overtime(since: end))
        #expect(try #require(third.activeTimer).overtime(at: clock.now) == 60)
        #expect(expired.count == 1)
    }

    @Test("Restore of a paused timer keeps it paused with the same time left")
    func restorePaused() {
        let first = launch()
        first.start(task: task, seconds: 1500)
        clock.advance(by: 600)
        first.pause()
        clock.advance(by: 5000)

        let second = launch()

        #expect(second.activeTimer?.phase == .paused(remaining: 900))
        #expect(expired.isEmpty)
    }

    @Test("Restore with a missing task goes idle and closes the session as deleted")
    func restoreWithAMissingTask() throws {
        let first = launch()
        first.start(task: task, seconds: 1500)
        let sessionID = try #require(first.activeTimer?.sessionID)
        clock.advance(by: 100)
        // The task goes away while the engine does not hear about it, as when the data changed while quit.
        service.timerHooks = nil
        service.deleteTask(task)

        let second = launch()

        #expect(second.state == .idle)
        #expect(defaults.object(forKey: key) == nil)
        let session = try #require(service.session(withID: sessionID))
        #expect(session.outcome == .deleted)
        #expect(session.activeSeconds == 100)
    }

    // MARK: - Helpers

    private func makeStore() -> ActiveTimerStore {
        ActiveTimerStore(defaults: defaults, key: key)
    }

    /// Builds an engine and a store as the app does at launch, and restores the saved state.
    private func launch() -> TimerEngine {
        let engine = TimerEngine(service: service, clock: clock)
        engine.onExpired = { [weak self] timer in
            self?.expired.append(timer)
        }
        makeStore().restore(into: engine)
        return engine
    }
}
