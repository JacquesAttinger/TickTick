// Last edited: 2026-09-24 15:17 PT

import Foundation
import os
import SwiftData

enum TaskServiceError: Error, Equatable {
    /// The Inbox can be renamed, but it cannot be deleted.
    case cannotDeleteInbox
}

/// Lets the timer engine react when a task is checked or deleted, wherever that happens.
@MainActor
protocol TaskTimerHooks: AnyObject {
    /// Called after `toggleDone` checks a task.
    func taskWasCompleted(_ task: TaskItem)
    /// Called before a task is deleted, also when `deleteNote` deletes it with its note.
    func taskWillBeDeleted(_ task: TaskItem)
}

/// Holds every rule for notes and tasks. Views and the timer engine change data only through this service.
///
/// Each operation saves at once. Only `deleteNote` throws. If a fetch or a save fails, the service logs
/// the error, and SwiftData's autosave tries the save again later.
@MainActor
final class TaskService {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "TaskService")

    let context: ModelContext
    /// The timer engine sets itself here, so checking or deleting the running task also ends its timer.
    weak var timerHooks: (any TaskTimerHooks)?
    private let now: () -> Date

    /// - Parameter now: the time source for `createdAt` and `completedAt`. Tests pass a fake one.
    init(context: ModelContext, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.now = now
    }

    // MARK: - Notes

    /// Adds a note after all other notes.
    @discardableResult
    func createNote(title: String) -> Note {
        let note = Note(title: title, sortIndex: lastNoteSortIndex() + 1, createdAt: now())
        context.insert(note)
        save()
        return note
    }

    func renameNote(_ note: Note, to title: String) {
        note.title = title
        save()
    }

    /// Deletes the note and its tasks. The tasks' timer sessions stay, with no task.
    func deleteNote(_ note: Note) throws {
        guard !note.isInbox else {
            throw TaskServiceError.cannotDeleteInbox
        }
        for task in note.tasks ?? [] {
            timerHooks?.taskWillBeDeleted(task)
        }
        context.delete(note)
        save()
    }

    // MARK: - Tasks

    /// Adds an open task at `index` in the note's open list, or at the end when `index` is nil.
    /// An index out of range goes to the nearest end.
    @discardableResult
    func createTask(title: String, in note: Note, at index: Int? = nil) -> TaskItem {
        let task = TaskItem(title: title, createdAt: now())
        context.insert(task)
        task.note = note
        place(task, atOpenIndex: index ?? .max, in: note)
        save()
        return task
    }

    func renameTask(_ task: TaskItem, to title: String) {
        task.title = title
        save()
    }

    /// Sets how long the task should take, or clears the estimate with nil.
    func setEstimate(_ seconds: TimeInterval?, for task: TaskItem) {
        task.estimateSeconds = seconds
        save()
    }

    /// Deletes the task. Its timer sessions stay, with no task.
    func deleteTask(_ task: TaskItem) {
        timerHooks?.taskWillBeDeleted(task)
        context.delete(task)
        save()
    }

    /// Checks the task (sets `completedAt`) or unchecks it (clears `completedAt`).
    /// `sortIndex` does not change, so an unchecked task goes back to its old place in the open list.
    func toggleDone(_ task: TaskItem) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? now() : nil
        save()
        if task.isDone {
            timerHooks?.taskWasCompleted(task)
        }
    }

    /// Moves the task so that it is at `index` in its note's open list after the move.
    /// An index out of range goes to the nearest end.
    func moveTask(_ task: TaskItem, to index: Int) {
        guard let note = task.note else {
            return
        }
        place(task, atOpenIndex: index, in: note)
        save()
    }

    // MARK: - Timer sessions

    /// Opens a session for one run of the timer on `task`. The timer engine closes it with `closeSession`.
    @discardableResult
    func startSession(for task: TaskItem, plannedSeconds: TimeInterval, at date: Date) -> TimerSession {
        let session = TimerSession(startedAt: date, plannedSeconds: plannedSeconds)
        context.insert(session)
        session.task = task
        save()
        return session
    }

    /// Ends the session. From then on, its `activeSeconds` count in `actualSeconds(for:)`.
    /// `plannedSeconds` is the final planned time, with every extension.
    func closeSession(
        _ session: TimerSession,
        endedAt: Date,
        activeSeconds: TimeInterval,
        plannedSeconds: TimeInterval,
        outcome: SessionOutcome
    ) {
        session.endedAt = endedAt
        session.activeSeconds = activeSeconds
        session.plannedSeconds = plannedSeconds
        session.outcome = outcome
        save()
    }

    // MARK: - Queries

    /// The task with this ID, or nil when it does not exist (for example, after it was deleted).
    func task(withID id: UUID) -> TaskItem? {
        first(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id }))
    }

    /// The session with this ID, or nil when it does not exist.
    func session(withID id: UUID) -> TimerSession? {
        first(FetchDescriptor<TimerSession>(predicate: #Predicate { $0.id == id }))
    }

    /// The note's open tasks, top to bottom.
    func openTasks(in note: Note) -> [TaskItem] {
        tasksInOrder(of: note).filter { !$0.isDone }
    }

    /// The note's done tasks, the most recently completed first.
    func completedTasks(in note: Note) -> [TaskItem] {
        tasksInOrder(of: note).filter(\.isDone).sorted { lhs, rhs in
            (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
        }
    }

    /// The task's actual time: the sum of `activeSeconds` over all its timer sessions.
    func actualSeconds(for task: TaskItem) -> TimeInterval {
        (task.sessions ?? []).filter { !$0.isDeleted }.reduce(0) { $0 + $1.activeSeconds }
    }

    // MARK: - Order

    /// All the note's tasks, open and done, by `sortIndex`. `createdAt` and `id` only break ties.
    private func tasksInOrder(of note: Note) -> [TaskItem] {
        (note.tasks ?? []).filter { !$0.isDeleted }.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex {
                return lhs.sortIndex < rhs.sortIndex
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Puts `task` just before the open task that will follow it, or at the very end of the note when
    /// no open task follows. Then it numbers all the note's tasks 0…n−1.
    /// Done tasks are numbered too, so each one stays between its old neighbors until it is unchecked.
    private func place(_ task: TaskItem, atOpenIndex openIndex: Int, in note: Note) {
        var ordered = tasksInOrder(of: note).filter { $0 !== task }
        let open = ordered.filter { !$0.isDone }
        let slot = min(max(openIndex, 0), open.count)
        if slot < open.count, let position = ordered.firstIndex(where: { $0 === open[slot] }) {
            ordered.insert(task, at: position)
        } else {
            ordered.append(task)
        }
        for (index, item) in ordered.enumerated() where item.sortIndex != index {
            item.sortIndex = index
        }
    }

    // MARK: - Storage

    private func lastNoteSortIndex() -> Int {
        first(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)]))?.sortIndex ?? -1
    }

    /// The first result of the fetch, or nil when there is none or the fetch fails.
    private func first<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> Model? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            let model = String(describing: Model.self)
            let reason = error.localizedDescription
            Self.logger.error("Fetching \(model, privacy: .public) failed: \(reason, privacy: .public)")
            return nil
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.logger.error("Saving failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
