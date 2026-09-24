// Last edited: 2026-09-24 15:18 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

@MainActor
struct TimerEngineTests {
    private let clock: TestClock
    private let store: ModelStore
    private let service: TaskService
    private let engine: TimerEngine
    private let inbox: Note

    init() throws {
        let clock = TestClock()
        self.clock = clock
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        inbox = try store.bootstrapInbox()
    }

    // MARK: - Start and switch

    @Test("start runs a timer on the task and opens a session")
    func startRunsATimer() throws {
        let task = service.createTask(title: "Write report", in: inbox)
        let start = clock.now

        #expect(engine.start(task: task, seconds: 1500) == .started)

        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .running(endDate: start.addingTimeInterval(1500)))
        #expect(timer.taskID == task.id)
        #expect(timer.plannedSeconds == 1500)
        #expect(timer.startedAt == start)
        #expect(engine.activeTask === task)
        let session = try #require(service.session(withID: timer.sessionID))
        #expect(session.task === task)
        #expect(session.startedAt == start)
        #expect(session.plannedSeconds == 1500)
        #expect(session.endedAt == nil)
    }

    @Test("Switch confirmation changes nothing")
    func switchConfirmationChangesNothing() throws {
        let first = service.createTask(title: "A", in: inbox)
        let second = service.createTask(title: "B", in: inbox)
        engine.start(task: first, seconds: 1500)
        let before = try #require(engine.activeTimer)
        clock.advance(by: 60)

        let result = engine.start(task: second, seconds: 300)

        #expect(result == .needsConfirmation(current: before))
        #expect(engine.state == .active(before))
        #expect(second.sessions?.isEmpty == true)
        #expect(try sessionCount() == 1)
    }

    @Test("Replace closes the old session as replaced")
    func replaceClosesTheOldSessionAsReplaced() throws {
        let first = service.createTask(title: "A", in: inbox)
        let second = service.createTask(title: "B", in: inbox)
        engine.start(task: first, seconds: 1500)
        let oldSessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 100)

        #expect(engine.start(task: second, seconds: 300, replacing: true) == .started)

        let old = try #require(service.session(withID: oldSessionID))
        #expect(old.outcome == .replaced)
        #expect(old.endedAt == clock.now)
        #expect(old.activeSeconds == 100)
        #expect(!first.isDone)
        let timer = try #require(engine.activeTimer)
        #expect(timer.taskID == second.id)
        #expect(timer.phase == .running(endDate: clock.now.addingTimeInterval(300)))
        #expect(service.session(withID: timer.sessionID)?.endedAt == nil)
    }

    // MARK: - Pause and resume

    @Test("Pause keeps the remaining time")
    func pauseKeepsTheRemainingTime() throws {
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        clock.advance(by: 600)

        engine.pause()
        clock.advance(by: 1000)

        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .paused(remaining: 900))
        #expect(timer.remaining(at: clock.now) == 900)
        #expect(timer.activeSeconds(at: clock.now) == 600)
        #expect(timer.lastResumedAt == nil)
    }

    @Test("Resume runs again with the remaining time")
    func resumeRunsWithTheRemainingTime() throws {
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        clock.advance(by: 600)
        engine.pause()
        clock.advance(by: 1000)

        engine.resume()

        let timer = try #require(engine.activeTimer)
        #expect(timer.phase == .running(endDate: clock.now.addingTimeInterval(900)))
        #expect(timer.lastResumedAt == clock.now)
    }

    @Test("pause, resume, stop, and done do nothing in the wrong phase")
    func operationsInTheWrongPhaseDoNothing() {
        var changes: [TimerState] = []
        engine.stateDidChange = { changes.append($0) }

        engine.pause()
        engine.resume()
        engine.stop()
        engine.done()
        #expect(engine.state == .idle)

        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 60)
        let running = engine.state
        engine.resume()
        #expect(engine.state == running)
        #expect(changes == [running])
    }

    // MARK: - Stop and done

    @Test("Stop closes the session as stopped and keeps the task open")
    func stopClosesTheSessionAsStopped() throws {
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 90)

        engine.stop()

        #expect(engine.state == .idle)
        let session = try #require(service.session(withID: sessionID))
        #expect(session.outcome == .stopped)
        #expect(session.activeSeconds == 90)
        #expect(session.endedAt == clock.now)
        #expect(!task.isDone)
        #expect(service.actualSeconds(for: task) == 90)
    }

    @Test("Done closes the session as done and checks the task")
    func doneChecksTheTask() throws {
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 1200)

        engine.done()

        #expect(engine.state == .idle)
        let session = try #require(service.session(withID: sessionID))
        #expect(session.outcome == .done)
        #expect(session.activeSeconds == 1200)
        #expect(task.isDone)
        #expect(task.completedAt == clock.now)
    }

    @Test("Every change calls stateDidChange with the new state")
    func everyChangeIsReported() {
        var changes: [TimerState] = []
        engine.stateDidChange = { changes.append($0) }
        let task = service.createTask(title: "A", in: inbox)

        engine.start(task: task, seconds: 60)
        engine.pause()
        engine.resume()
        engine.stop()

        #expect(changes.count == 4)
        #expect(changes.last == .idle)
    }

    // MARK: - Check and delete hooks

    @Test("Checking the running task is the same as Done")
    func checkingTheRunningTaskIsDone() throws {
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 100)

        service.toggleDone(task)

        #expect(engine.state == .idle)
        #expect(task.isDone)
        let session = try #require(service.session(withID: sessionID))
        #expect(session.outcome == .done)
        #expect(session.activeSeconds == 100)
    }

    @Test("Done checks the task one time, with no loop through the check hook")
    func doneDoesNotLoopThroughTheHook() {
        var changes: [TimerState] = []
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        engine.stateDidChange = { changes.append($0) }

        engine.done()

        #expect(changes == [.idle])
        #expect(task.isDone)
        #expect(task.sessions?.count == 1)
    }

    @Test("Checking or deleting another task does not touch the timer")
    func otherTasksDoNotTouchTheTimer() {
        let running = service.createTask(title: "A", in: inbox)
        let other = service.createTask(title: "B", in: inbox)
        let third = service.createTask(title: "C", in: inbox)
        engine.start(task: running, seconds: 1500)
        let state = engine.state

        service.toggleDone(other)
        service.deleteTask(third)

        #expect(engine.state == state)
    }

    @Test("Deleting the running task stops the timer and saves the session as deleted")
    func deletingTheRunningTaskStopsTheTimer() throws {
        let task = service.createTask(title: "A", in: inbox)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)
        clock.advance(by: 50)

        service.deleteTask(task)

        #expect(engine.state == .idle)
        let session = try #require(service.session(withID: sessionID))
        #expect(session.outcome == .deleted)
        #expect(session.activeSeconds == 50)
        #expect(session.task == nil)
    }

    @Test("Deleting the note of the running task stops the timer and saves the session as deleted")
    func deletingTheNoteStopsTheTimer() throws {
        let note = service.createNote(title: "Errands")
        let task = service.createTask(title: "Buy milk", in: note)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)

        try service.deleteNote(note)

        #expect(engine.state == .idle)
        #expect(service.session(withID: sessionID)?.outcome == .deleted)
    }

    // MARK: - Helpers

    private func sessionCount() throws -> Int {
        try store.context.fetchCount(FetchDescriptor<TimerSession>())
    }
}
