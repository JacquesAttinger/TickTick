// Last edited: 2026-09-24 19:20 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// The Notes window's task list on real data: an in-memory store, the real task service, and an engine with a
/// test clock.
@MainActor
struct TaskListModelTests {
    private let clock = TestClock()
    private let store: ModelStore
    private let service: TaskService
    private let engine: TimerEngine
    private let note: Note
    private let model: TaskListModel

    init() throws {
        let clock = clock
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        _ = try store.bootstrapInbox()
        note = service.createNote(title: "Work")
        model = TaskListModel(noteID: note.id, service: service, engine: engine)
    }

    /// Types `title` in the draft row and presses Return, like the view does.
    private func submitDraft(_ title: String) {
        model.draftText = title
        model.send(.submitDraft(title: model.draftText))
    }

    @Test("Task, Return, 25, Return: the task is last in the note with a 25 min estimate, and its timer runs")
    func fullFlowStartsATimer() throws {
        let older = service.createTask(title: "Older task", in: note)
        model.send(.tasksChanged([older.id]))

        submitDraft("Write intro")
        let task = try #require(service.openTasks(in: note).last)
        #expect(model.draftText.isEmpty)
        #expect(model.flow.inline == .prompt(taskID: task.id))
        model.send(.startRequested(seconds: 1500))

        #expect(task.title == "Write intro")
        #expect(service.openTasks(in: note) == [older, task])
        #expect(task.estimateSeconds == 1500)
        let timer = try #require(engine.activeTimer)
        #expect(timer.taskID == task.id)
        #expect(timer.phase == .running(endDate: clock.now.addingTimeInterval(1500)))
        #expect(model.flow.inline == nil)
        #expect(model.flow.focus == .draft)
        #expect(model.activeTimer(for: task) == timer)
        #expect(model.activeTimer(for: older) == nil)
    }

    @Test("Esc in the prompt keeps the task with no timer and no estimate")
    func escapeKeepsTheTask() throws {
        submitDraft("Outline")
        model.send(.skipDuration)

        let task = try #require(service.openTasks(in: note).first)
        #expect(task.title == "Outline")
        #expect(task.estimateSeconds == nil)
        #expect(engine.activeTimer == nil)
    }

    @Test("▶ while a timer runs asks first. Cancel keeps the old timer and the typed duration")
    func switchQuestionCancel() {
        let running = service.createTask(title: "Write intro", in: note)
        let other = service.createTask(title: "Research", in: note)
        engine.start(task: running, seconds: 1500)
        clock.advance(by: 180)
        model.send(.tasksChanged([running.id, other.id]))

        model.send(.playTapped(id: other.id))
        #expect(model.durationText.isEmpty)
        model.durationText = "10"
        model.send(.startRequested(seconds: 600))

        #expect(model.flow.inline == .confirmSwitch(taskID: other.id, pendingSeconds: 600))
        #expect(model.switchMessage(at: clock.now) == "Stop “Write intro” (22 min left) and start “Research”?")
        #expect(other.estimateSeconds == nil)

        model.send(.cancelSwitch)
        #expect(model.flow.inline == .prompt(taskID: other.id))
        #expect(model.durationText == "10")
        #expect(engine.activeTimer?.taskID == running.id)
        #expect(model.switchMessage(at: clock.now) == nil)
    }

    @Test("Stop & Start replaces the old timer: the old session ends as replaced, and the new task has the estimate")
    func switchQuestionConfirm() throws {
        let running = service.createTask(title: "Write intro", in: note)
        let other = service.createTask(title: "Research", in: note)
        engine.start(task: running, seconds: 1500)
        let oldSessionID = try #require(engine.activeTimer?.sessionID)
        model.send(.tasksChanged([running.id, other.id]))

        model.send(.playTapped(id: other.id))
        model.send(.startRequested(seconds: 600))
        model.send(.confirmSwitch)

        #expect(engine.activeTimer?.taskID == other.id)
        #expect(other.estimateSeconds == 600)
        #expect(service.session(withID: oldSessionID)?.outcome == .replaced)
        #expect(model.flow.inline == nil)
    }

    @Test("A new prompt starts empty")
    func newPromptStartsEmpty() {
        let task = service.createTask(title: "Research", in: note)
        model.send(.tasksChanged([task.id]))
        model.send(.playTapped(id: task.id))
        model.durationText = "abc"
        model.send(.skipDuration)

        model.send(.playTapped(id: task.id))

        #expect(model.durationText.isEmpty)
    }

    @Test("Checking the running task is Done: the timer ends and the task leaves the open list")
    func checkingTheRunningTaskIsDone() throws {
        let task = service.createTask(title: "Write intro", in: note)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)

        model.toggleDone(task)

        #expect(engine.activeTimer == nil)
        #expect(service.session(withID: sessionID)?.outcome == .done)
        #expect(model.openTasks(in: note).isEmpty)
    }

    @Test("Deleting the running task stops the timer, and the session ends as deleted")
    func deletingTheRunningTaskStops() throws {
        let task = service.createTask(title: "Write intro", in: note)
        engine.start(task: task, seconds: 1500)
        let sessionID = try #require(engine.activeTimer?.sessionID)

        model.delete(task)

        #expect(engine.activeTimer == nil)
        #expect(service.session(withID: sessionID)?.outcome == .deleted)
        #expect(model.openTasks(in: note).isEmpty)
    }

    @Test("⌫ on an empty row deletes the task, and the rename on the lost focus does nothing")
    func deleteBackwardDeletesTheTask() {
        let keep = service.createTask(title: "Outline", in: note)
        let empty = service.createTask(title: "Draft", in: note)
        model.send(.tasksChanged([keep.id, empty.id]))

        model.send(.deleteBackwardOnEmpty(id: empty.id))
        model.send(.rowFocusLost(id: empty.id, title: ""))

        #expect(model.openTasks(in: note) == [keep])
        #expect(model.flow.focus == .task(keep.id))
    }

    @Test("Return and focus loss save a new title, and an unchanged title saves nothing")
    func renameThroughTheFlow() {
        let task = service.createTask(title: "Outline", in: note)
        model.send(.tasksChanged([task.id]))

        model.send(.submitRow(id: task.id, title: "  Outline v2 "))
        #expect(task.title == "Outline v2")
        model.send(.rowFocusLost(id: task.id, title: "Outline v3"))
        #expect(task.title == "Outline v3")
        model.send(.rowFocusLost(id: task.id, title: " "))
        #expect(task.title == "Outline v3")
    }

    @Test("A typed draft saves on focus loss, with no prompt, and the draft row empties")
    func draftFocusLossSaves() throws {
        model.draftText = "Research"
        model.send(.draftFocusLost(title: model.draftText))

        let task = try #require(service.openTasks(in: note).first)
        #expect(task.title == "Research")
        #expect(model.draftText.isEmpty)
        #expect(model.flow.inline == nil)
        #expect(model.flow.rows == [task.id])
    }
}
