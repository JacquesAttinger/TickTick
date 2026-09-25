// Last edited: 2026-09-24 17:58 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// The quick-add flow on real data: an in-memory store, the real task service, and an engine with a test clock.
@MainActor
struct QuickAddSessionTests {
    private let clock = TestClock()
    private let store: ModelStore
    private let service: TaskService
    private let engine: TimerEngine
    private let inbox: Note
    private let session: QuickAddSession
    private let closes: CloseCounter

    init() throws {
        let clock = clock
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        inbox = try store.bootstrapInbox()
        let store = store
        session = QuickAddSession(service: service, engine: engine) { try store.bootstrapInbox() }
        let closes = CloseCounter()
        session.onClose = { closes.count += 1 }
        self.closes = closes
    }

    @Test("Task, Return, 25, Return: the task is last in the Inbox with a 25 min estimate, and its timer runs")
    func fullFlowStartsATimer() throws {
        let other = service.createTask(title: "Older task", in: inbox)

        session.send(.submitTask("Write cover letter"))
        session.send(.startRequested(seconds: 1500))

        let task = try #require(session.task)
        #expect(task.title == "Write cover letter")
        #expect(task.note === inbox)
        #expect(service.openTasks(in: inbox) == [other, task])
        #expect(task.estimateSeconds == 1500)
        let timer = try #require(engine.activeTimer)
        #expect(timer.taskID == task.id)
        #expect(timer.phase == .running(endDate: clock.now.addingTimeInterval(1500)))
        #expect(session.step == .closed)
        #expect(closes.count == 1)
    }

    @Test("Esc on step 1 saves nothing")
    func escapeOnStepOneSavesNothing() {
        session.taskText = "Draft"
        session.send(.escapeOnTask)

        #expect(service.openTasks(in: inbox).isEmpty)
        #expect(engine.activeTimer == nil)
        #expect(closes.count == 1)
    }

    @Test("Esc on step 2 keeps the task in the Inbox with no timer and no estimate")
    func escapeOnStepTwoKeepsTheTask() throws {
        session.send(.submitTask("Write cover letter"))
        session.send(.skipDuration)

        let task = try #require(service.openTasks(in: inbox).first)
        #expect(task.title == "Write cover letter")
        #expect(task.estimateSeconds == nil)
        #expect(engine.activeTimer == nil)
        #expect(closes.count == 1)
    }

    @Test("With a timer running, the start asks first and changes nothing")
    func activeTimerAsksFirst() throws {
        let running = startRunningTimer(title: "Debug timer", seconds: 720)
        let before = engine.state

        session.send(.submitTask("Write cover letter"))
        session.send(.startRequested(seconds: 1500))

        #expect(session.step == .confirmSwitch(pendingSeconds: 1500))
        #expect(engine.state == before)
        #expect(engine.activeTask === running)
        #expect(session.task?.estimateSeconds == nil)
        #expect(closes.count == 0)
        let message = try #require(session.switchMessage(at: clock.now))
        #expect(message == "Stop “Debug timer” (12 min left) and start “Write cover letter”?")
    }

    @Test("Stop & Start replaces the old timer with the new task's timer")
    func confirmSwitchReplacesTheTimer() throws {
        let running = startRunningTimer(title: "Debug timer", seconds: 720)
        let oldSessionID = try #require(engine.activeTimer?.sessionID)
        session.send(.submitTask("Write cover letter"))
        session.send(.startRequested(seconds: 1500))

        session.send(.confirmSwitch)

        let task = try #require(session.task)
        #expect(engine.activeTask === task)
        #expect(task.estimateSeconds == 1500)
        #expect(service.session(withID: oldSessionID)?.outcome == .replaced)
        #expect(!running.isDone)
        #expect(closes.count == 1)
    }

    @Test("Cancel keeps the old timer and the typed duration, and returns to step 2")
    func cancelSwitchKeepsTheOldTimer() {
        let running = startRunningTimer(title: "Debug timer", seconds: 720)
        session.send(.submitTask("Write cover letter"))
        session.durationText = "25"
        session.send(.startRequested(seconds: 1500))

        session.send(.cancelSwitch)

        #expect(session.step == .duration)
        #expect(session.durationText == "25")
        #expect(engine.activeTask === running)
        #expect(closes.count == 0)
    }

    @Test("The switch message has no text when no timer is active")
    func noSwitchMessageWhenIdle() {
        #expect(session.switchMessage(at: clock.now) == nil)
    }

    private func startRunningTimer(title: String, seconds: TimeInterval) -> TaskItem {
        let task = service.createTask(title: title, in: inbox)
        engine.start(task: task, seconds: seconds)
        return task
    }
}

/// Counts the panel closes that a session asks for.
@MainActor
private final class CloseCounter {
    var count = 0
}
