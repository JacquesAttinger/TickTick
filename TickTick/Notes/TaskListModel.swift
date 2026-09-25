// Last edited: 2026-09-24 19:20 PT

import Foundation
import Observation
import os

/// The task list of one note in the Notes window: the flow, the text of the draft row, and the typed duration.
///
/// `NoteDetailView` shows it and sends it events. It runs the flow's effects on the real data: tasks change through
/// `TaskService`, and timers start through `TimerEngine`. Checking or deleting the running task needs no special
/// case here: the engine's `TaskTimerHooks` turn them into Done and a stop.
@Observable
@MainActor
final class TaskListModel {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "TaskList")

    let noteID: UUID
    private(set) var flow = TaskListFlow()
    /// The text of the empty row at the bottom.
    var draftText = ""
    /// Owned here, not by the duration field, so a cancelled switch question gives the typed duration back.
    var durationText = ""

    @ObservationIgnored private let service: TaskService
    @ObservationIgnored private let engine: TimerEngine

    init(noteID: UUID, service: TaskService, engine: TimerEngine) {
        self.noteID = noteID
        self.service = service
        self.engine = engine
    }

    /// The note's open tasks, top to bottom. Read it in a view's body, so the view follows every change to them.
    func openTasks(in note: Note) -> [TaskItem] {
        service.openTasks(in: note)
    }

    /// Feeds one event to the flow and runs the effects it returns.
    func send(_ event: TaskListFlow.Event) {
        let promptBefore = flow.inline?.taskID
        let effects = flow.handle(event)
        // A prompt that opens on another task starts empty. A cancelled switch question keeps the text.
        if let promptTask = flow.inline?.taskID, promptTask != promptBefore {
            durationText = ""
        }
        for effect in effects {
            run(effect)
        }
    }

    /// The checkbox. Checking the running task is the same as Done.
    func toggleDone(_ task: TaskItem) {
        service.toggleDone(task)
    }

    /// "Delete" in the context menu. It asks nothing: one task is cheap to type again.
    /// Deleting the running task stops its timer.
    func delete(_ task: TaskItem) {
        service.deleteTask(task)
    }

    /// The active timer when it belongs to `task`, or nil.
    func activeTimer(for task: TaskItem) -> ActiveTimer? {
        engine.activeTimer.flatMap { $0.taskID == task.id ? $0 : nil }
    }

    /// The switch question for the active timer at `now`, or nil when no question shows.
    func switchMessage(at now: Date) -> String? {
        guard case let .confirmSwitch(taskID, _)? = flow.inline, let current = engine.activeTimer else {
            return nil
        }
        return SwitchConfirmation.message(
            current: current,
            currentTitle: engine.activeTask?.title ?? "",
            newTitle: service.task(withID: taskID)?.title ?? "",
            now: now
        )
    }

    private func run(_ effect: TaskListFlow.Effect) {
        switch effect {
        case let .createTask(title):
            createTask(title: title)
        case let .renameTask(id, title):
            if let task = service.task(withID: id), task.title != title {
                service.renameTask(task, to: title)
            }
        case let .deleteTask(id):
            if let task = service.task(withID: id) {
                service.deleteTask(task)
            }
        case let .startTimer(taskID, seconds, replacing):
            startTimer(taskID: taskID, seconds: seconds, replacing: replacing)
        }
    }

    private func createTask(title: String) {
        draftText = ""
        guard let note = service.note(withID: noteID) else {
            Self.logger.error("The note of the new task is gone")
            return
        }
        let task = service.createTask(title: title, in: note)
        send(.taskCreated(id: task.id))
    }

    /// Starts the timer. The estimate is set only when the timer really starts, so a cancelled switch leaves the
    /// task as it was (the same rule as quick-add).
    private func startTimer(taskID: UUID, seconds: TimeInterval, replacing: Bool) {
        guard let task = service.task(withID: taskID) else {
            return
        }
        switch engine.start(task: task, seconds: seconds, replacing: replacing) {
        case .started:
            service.setEstimate(seconds, for: task)
            send(.timerStarted)
        case .needsConfirmation:
            send(.engineNeedsConfirmation)
        }
    }
}
