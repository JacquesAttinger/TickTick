// Last edited: 2026-09-28 17:05 PT

import Foundation
import Observation
import os

/// The task list of one note in the Notes window: the flow, the text of the draft row, the typed duration, and the
/// drag that reorders the rows.
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
    /// The task whose handle is being dragged. A drag that is cancelled leaves it set until the next drag starts.
    private(set) var draggedTaskID: UUID?
    /// The gap where the dragged task would land, for the drop line: 0 is above the first row, and `rows.count` is
    /// below the last one. Nil when the pointer is not over the list, or when a drop there would not move the task.
    private(set) var dropGap: Int?

    @ObservationIgnored private let service: TaskService
    @ObservationIgnored private let engine: TimerEngine

    init(noteID: UUID, service: TaskService, engine: TimerEngine) {
        self.noteID = noteID
        self.service = service
        self.engine = engine
    }

    /// All the note's tasks, open and done, top to bottom. Read it in a view's body, so the view follows every
    /// change to them.
    func tasks(in note: Note) -> [TaskItem] {
        service.tasks(in: note)
    }

    /// The flow's event for the tasks as they are now: their order, and which are done.
    static func tasksChanged(_ tasks: [TaskItem]) -> TaskListFlow.Event {
        .tasksChanged(tasks.map(\.id), done: Set(tasks.filter(\.isDone).map(\.id)))
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

    /// The row's badge at `now`, for example `45m est · 52m actual`, or nil when the task has neither.
    /// The actual time counts the running timer too, so it goes up live.
    func timeBadge(for task: TaskItem, at now: Date) -> String? {
        let running = activeTimer(for: task)?.activeSeconds(at: now) ?? 0
        return TimeFormatting.taskBadge(
            estimateSeconds: task.estimateSeconds,
            actualSeconds: service.actualSeconds(for: task) + running
        )
    }

    // MARK: - Reorder

    /// A drag on the row's handle started.
    func beginDrag(_ task: TaskItem) {
        draggedTaskID = task.id
        dropGap = nil
    }

    /// The pointer is over `gap` during a drag, or left the list (nil). Shows the drop line only where a drop
    /// would move the task.
    func dragMoved(toGap gap: Int?) {
        dropGap = gap.flatMap { gap in destination(forGap: gap) == nil ? nil : gap }
    }

    /// Drops the dragged task in `gap`. Returns false, and changes nothing, when the drop would not move it.
    @discardableResult
    func drop(atGap gap: Int) -> Bool {
        defer {
            draggedTaskID = nil
            dropGap = nil
        }
        guard let index = destination(forGap: gap), let id = draggedTaskID, let task = service.task(withID: id) else {
            return false
        }
        service.moveTask(task, to: index)
        return true
    }

    /// Where the dragged task goes when dropped in `gap`, as an index for `TaskService.moveTask`, or nil when the
    /// drop would not move it (the gaps just above and below the task itself).
    private func destination(forGap gap: Int) -> Int? {
        guard let id = draggedTaskID, let source = flow.rows.firstIndex(of: id) else {
            return nil
        }
        return Self.destination(from: source, gap: min(max(gap, 0), flow.rows.count))
    }

    /// The index after the move for a task at `source` that is dropped in `gap`, or nil when it would not move.
    static func destination(from source: Int, gap: Int) -> Int? {
        if gap == source || gap == source + 1 {
            return nil
        }
        return gap > source ? gap - 1 : gap
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
