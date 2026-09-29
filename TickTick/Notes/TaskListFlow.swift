// Last edited: 2026-09-28 16:50 PT

import Foundation

/// The keyboard and timer rules of one note's task list, as a pure state machine. `TaskListModel` feeds it events
/// and runs the effects it returns, so tests can check every Return, Esc, ⌫, arrow, ▶, and switch rule without a
/// window.
///
/// The list is all the note's tasks, open and done, then one empty draft row at the bottom. A checked task stays in
/// its row, like in an Apple Notes checklist, but it gets no prompt. Return on the draft saves a new task
/// and opens the "How long?" prompt under it (product decision 6). Return in the prompt starts the timer, and Esc
/// keeps the task without a timer. ▶ opens the same prompt on any row. When another timer is active, the prompt
/// asks first (decision 8). `focus` always names a row that exists: a task in `rows`, or the draft.
struct TaskListFlow: Equatable {
    enum Row: Hashable {
        case task(UUID)
        /// The empty row at the bottom. It is not a saved task.
        case draft
    }

    /// What shows under a task row. While it shows, it has the keyboard, not the row.
    enum Inline: Equatable {
        /// The "How long?" prompt.
        case prompt(taskID: UUID)
        /// Another timer is active. `pendingSeconds` is the new timer's duration.
        case confirmSwitch(taskID: UUID, pendingSeconds: TimeInterval)

        var taskID: UUID {
            switch self {
            case let .prompt(taskID), let .confirmSwitch(taskID, _): taskID
            }
        }
    }

    enum Event: Equatable {
        /// The note's tasks, top to bottom, and which of them are done, after a change (also a change from outside
        /// the window, like Done in the popover).
        case tasksChanged([UUID], done: Set<UUID> = [])
        /// Return on the draft row.
        case submitDraft(title: String)
        /// The draft row lost the keyboard focus.
        case draftFocusLost(title: String)
        /// `createTask` saved the task with this ID.
        case taskCreated(id: UUID)
        /// Return on a task row.
        case submitRow(id: UUID, title: String)
        /// A task row lost the keyboard focus.
        case rowFocusLost(id: UUID, title: String)
        /// ▶ (or ⌘↩) on a task row.
        case playTapped(id: UUID)
        /// Return on a valid duration, or a chip click.
        case startRequested(seconds: TimeInterval)
        /// Esc in the prompt.
        case skipDuration
        /// The engine started the timer.
        case timerStarted
        /// The engine did not start the timer, because another timer is active.
        case engineNeedsConfirmation
        /// "Stop & Start" (or Return) on the switch question.
        case confirmSwitch
        /// "Cancel" (or Esc) on the switch question.
        case cancelSwitch
        /// ⌫ on a task row with no text.
        case deleteBackwardOnEmpty(id: UUID)
        /// ⌫ on the draft row with no text.
        case deleteBackwardOnEmptyDraft
        case moveUp
        case moveDown
        /// A click put the keyboard focus in a row.
        case focusChanged(Row)
    }

    enum Effect: Equatable {
        /// Add an open task with this title at the end of the note. Send `taskCreated` back with its ID.
        case createTask(title: String)
        case renameTask(id: UUID, title: String)
        case deleteTask(id: UUID)
        /// Send `timerStarted` or `engineNeedsConfirmation` back with the result.
        case startTimer(taskID: UUID, seconds: TimeInterval, replacing: Bool)
    }

    /// The IDs of the note's tasks, open and done, top to bottom. The draft row comes after them.
    private(set) var rows: [UUID] = []
    /// The rows whose task is done. ▶ does nothing on them.
    private(set) var done: Set<UUID> = []
    /// The row with the keyboard focus, or the row under which `inline` shows.
    private(set) var focus: Row = .draft
    private(set) var inline: Inline?
    /// The duration of the start that waits for the engine's answer.
    private var pendingSeconds: TimeInterval?
    /// True from a Return on the draft until its task is saved, so the new task gets the prompt.
    private var promptsNewTask = false

    /// Moves to the next state and returns what the caller must do, in order.
    mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .tasksChanged, .submitDraft, .draftFocusLost, .taskCreated:
            handleList(event)
        case .submitRow, .rowFocusLost, .deleteBackwardOnEmpty, .deleteBackwardOnEmptyDraft:
            handleRow(event)
        case .playTapped, .startRequested, .skipDuration, .timerStarted, .engineNeedsConfirmation, .confirmSwitch,
             .cancelSwitch:
            handleInline(event)
        case .moveUp, .moveDown, .focusChanged:
            handleFocus(event)
        }
    }

    // MARK: - Rows

    private mutating func handleList(_ event: Event) -> [Effect] {
        switch event {
        case let .tasksChanged(ids, done):
            sync(ids, done: done)
        case let .submitDraft(text):
            guard let title = NotesSidebarModel.title(from: text) else {
                return []
            }
            promptsNewTask = true
            return [.createTask(title: title)]
        case let .draftFocusLost(text):
            // A click elsewhere keeps typed work: the task is saved with no timer and no prompt.
            guard let title = NotesSidebarModel.title(from: text) else {
                return []
            }
            promptsNewTask = false
            return [.createTask(title: title)]
        case let .taskCreated(id):
            taskCreated(id)
        default:
            break
        }
        return []
    }

    private mutating func handleRow(_ event: Event) -> [Effect] {
        switch event {
        case let .submitRow(id, title) where rows.contains(id):
            let effects = rename(id, title)
            focusRow(neighbor(of: .task(id), by: 1))
            return effects
        case let .rowFocusLost(id, title) where rows.contains(id):
            return rename(id, title)
        case let .deleteBackwardOnEmpty(id):
            return deleteBackward(id)
        case .deleteBackwardOnEmptyDraft:
            if let last = rows.last {
                focusRow(.task(last))
            }
        default:
            break
        }
        return []
    }

    private mutating func sync(_ ids: [UUID], done: Set<UUID>) {
        let old = rows
        rows = ids
        self.done = done
        // The prompt's task was deleted, or checked (for example with Done in the popover).
        if let inline, !ids.contains(inline.taskID) || done.contains(inline.taskID) {
            closeInline()
        }
        // The focused task left the list (deleted): the row that is now in its place gets the focus.
        if case let .task(id) = focus, !ids.contains(id) {
            let index = old.firstIndex(of: id) ?? ids.count
            focus = index < ids.count ? .task(ids[index]) : .draft
        }
    }

    private mutating func taskCreated(_ id: UUID) {
        if !rows.contains(id) {
            rows.append(id)
        }
        if promptsNewTask {
            promptsNewTask = false
            open(.prompt(taskID: id))
        }
    }

    /// Saves a new title. An empty or blank title keeps the old one, so it saves nothing.
    private func rename(_ id: UUID, _ text: String) -> [Effect] {
        NotesSidebarModel.title(from: text).map { [.renameTask(id: id, title: $0)] } ?? []
    }

    /// Deletes the row, and the focus goes to the row above (or to the next row when it was the first).
    private mutating func deleteBackward(_ id: UUID) -> [Effect] {
        guard let index = rows.firstIndex(of: id) else {
            return []
        }
        rows.remove(at: index)
        if index > 0 {
            focusRow(.task(rows[index - 1]))
        } else {
            focusRow(rows.first.map(Row.task) ?? .draft)
        }
        return [.deleteTask(id: id)]
    }

    // MARK: - Prompt and switch question

    private mutating func handleInline(_ event: Event) -> [Effect] {
        switch (inline, event) {
        case let (_, .playTapped(id)):
            if rows.contains(id), !done.contains(id) {
                open(.prompt(taskID: id))
            }
        case let (.prompt(id)?, .startRequested(seconds)):
            pendingSeconds = seconds
            return [.startTimer(taskID: id, seconds: seconds, replacing: false)]
        case let (.prompt(id)?, .engineNeedsConfirmation):
            if let pendingSeconds {
                inline = .confirmSwitch(taskID: id, pendingSeconds: pendingSeconds)
            }
        case let (.confirmSwitch(id, seconds)?, .confirmSwitch):
            return [.startTimer(taskID: id, seconds: seconds, replacing: true)]
        case let (.confirmSwitch(id, _)?, .cancelSwitch):
            // Back to the prompt. The caller keeps the typed duration.
            pendingSeconds = nil
            inline = .prompt(taskID: id)
        case (.prompt?, .skipDuration), (.some, .timerStarted):
            focusRow(.draft)
        default:
            break
        }
        return []
    }

    private mutating func open(_ newInline: Inline) {
        pendingSeconds = nil
        inline = newInline
        focus = .task(newInline.taskID)
    }

    private mutating func closeInline() {
        inline = nil
        pendingSeconds = nil
    }

    // MARK: - Focus

    private mutating func handleFocus(_ event: Event) -> [Effect] {
        switch event {
        case .moveUp:
            focusRow(neighbor(of: focus, by: -1))
        case .moveDown:
            focusRow(neighbor(of: focus, by: 1))
        case let .focusChanged(row):
            if exists(row), row != focus || inline != nil {
                focusRow(row)
            }
        default:
            break
        }
        return []
    }

    /// Every focus move by the keyboard or a click also closes the prompt or the question, because it had the
    /// keyboard. The task stays, with no timer.
    private mutating func focusRow(_ row: Row) {
        closeInline()
        focus = row
    }

    private func exists(_ row: Row) -> Bool {
        switch row {
        case .draft: true
        case let .task(id): rows.contains(id)
        }
    }

    /// The row `offset` rows away from `row`, clamped to the first task row and the draft row.
    private func neighbor(of row: Row, by offset: Int) -> Row {
        let all = rows.map(Row.task) + [.draft]
        let index = all.firstIndex(of: row) ?? all.count - 1
        return all[min(max(index + offset, 0), all.count - 1)]
    }
}
