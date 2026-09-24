// Last edited: 2026-09-24 15:04 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// Returns a time one second later on each call, so every created or completed item has a clear order.
@MainActor
private final class SteppingClock {
    private var current = Date(timeIntervalSinceReferenceDate: 0)

    func next() -> Date {
        current.addTimeInterval(1)
        return current
    }
}

@MainActor
struct TaskServiceTests {
    private let store: ModelStore
    private let service: TaskService
    private let inbox: Note

    init() throws {
        let clock = SteppingClock()
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context, now: clock.next)
        inbox = try store.bootstrapInbox()
    }

    // MARK: - Notes

    @Test("createNote adds each note after the others")
    func createNoteAppends() throws {
        let errands = service.createNote(title: "Errands")
        let work = service.createNote(title: "Work")

        #expect(errands.sortIndex == 1)
        #expect(work.sortIndex == 2)
        #expect(try allNotes().map(\.title) == ["Inbox", "Errands", "Work"])
    }

    @Test("renameNote changes the title, also for the Inbox")
    func renameNoteChangesTitle() {
        let note = service.createNote(title: "Erands")

        service.renameNote(note, to: "Errands")
        service.renameNote(inbox, to: "Capture")

        #expect(note.title == "Errands")
        #expect(inbox.title == "Capture")
        #expect(inbox.isInbox)
    }

    @Test("deleteNote deletes the note and its tasks, and keeps their sessions")
    func deleteNoteCascadesToTasksOnly() throws {
        let note = service.createNote(title: "Errands")
        let task = TaskItem(title: "Buy milk")
        store.context.insert(task)
        task.note = note
        addSession(to: task, activeSeconds: 60)

        try service.deleteNote(note)

        #expect(try allNotes().map(\.title) == ["Inbox"])
        #expect(try store.context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
        let sessions = try store.context.fetch(FetchDescriptor<TimerSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.task == nil)
    }

    @Test("Inbox cannot be deleted")
    func inboxCannotBeDeleted() throws {
        #expect(throws: TaskServiceError.cannotDeleteInbox) {
            try service.deleteNote(inbox)
        }
        #expect(try allNotes().map(\.title) == ["Inbox"])
    }

    // MARK: - Create, rename, delete tasks

    @Test("createTask adds a task at the end when no index is given")
    func createTaskAppends() {
        let task = service.createTask(title: "A", in: inbox)
        service.createTask(title: "B", in: inbox)
        service.createTask(title: "C", in: inbox)

        #expect(openTitles(in: inbox) == ["A", "B", "C"])
        #expect(task.note === inbox)
        #expect(!task.isDone)
        #expect(task.completedAt == nil)
    }

    @Test("createTask inserts a task at the given index")
    func createTaskInsertsAtIndex() {
        service.createTask(title: "A", in: inbox)
        service.createTask(title: "C", in: inbox)

        service.createTask(title: "B", in: inbox, at: 1)
        service.createTask(title: "Top", in: inbox, at: 0)

        #expect(openTitles(in: inbox) == ["Top", "A", "B", "C"])
    }

    @Test("createTask puts an index out of range at the nearest end")
    func createTaskClampsIndex() {
        service.createTask(title: "A", in: inbox)

        service.createTask(title: "Last", in: inbox, at: 99)
        service.createTask(title: "First", in: inbox, at: -3)

        #expect(openTitles(in: inbox) == ["First", "A", "Last"])
    }

    @Test("renameTask changes the title")
    func renameTaskChangesTitle() {
        let task = service.createTask(title: "Wirte report", in: inbox)

        service.renameTask(task, to: "Write report")

        #expect(task.title == "Write report")
    }

    @Test("deleteTask removes the task and keeps its sessions")
    func deleteTaskKeepsSessions() throws {
        service.createTask(title: "A", in: inbox)
        let task = service.createTask(title: "B", in: inbox)
        addSession(to: task, activeSeconds: 90)

        service.deleteTask(task)

        #expect(openTitles(in: inbox) == ["A"])
        let sessions = try store.context.fetch(FetchDescriptor<TimerSession>())
        #expect(sessions.map(\.activeSeconds) == [90])
        #expect(sessions.first?.task == nil)
    }

    @Test("Every change is saved at once")
    func everyChangeIsSavedAtOnce() throws {
        let note = service.createNote(title: "Errands")
        #expect(!store.context.hasChanges)
        service.renameNote(note, to: "Chores")
        #expect(!store.context.hasChanges)

        let task = service.createTask(title: "A", in: note)
        service.createTask(title: "B", in: note)
        #expect(!store.context.hasChanges)
        service.renameTask(task, to: "A2")
        #expect(!store.context.hasChanges)
        service.moveTask(task, to: 1)
        #expect(!store.context.hasChanges)
        service.toggleDone(task)
        #expect(!store.context.hasChanges)
        service.deleteTask(task)
        #expect(!store.context.hasChanges)

        try service.deleteNote(note)
        #expect(!store.context.hasChanges)
    }

    // MARK: - Check and uncheck

    @Test("toggleDone checks a task, sets completedAt, and keeps sortIndex")
    func toggleDoneChecks() {
        service.createTask(title: "A", in: inbox)
        let task = service.createTask(title: "B", in: inbox)
        let sortIndex = task.sortIndex

        service.toggleDone(task)

        #expect(task.isDone)
        #expect(task.completedAt != nil)
        #expect(task.sortIndex == sortIndex)
        #expect(openTitles(in: inbox) == ["A"])
        #expect(service.completedTasks(in: inbox).map(\.title) == ["B"])
    }

    @Test("toggleDone unchecks a task and clears completedAt")
    func toggleDoneUnchecks() {
        let task = service.createTask(title: "A", in: inbox)
        service.toggleDone(task)

        service.toggleDone(task)

        #expect(!task.isDone)
        #expect(task.completedAt == nil)
        #expect(service.completedTasks(in: inbox).isEmpty)
    }

    @Test("uncheck returns the task to its old position")
    func uncheckReturnsToOldPosition() throws {
        for title in ["A", "B", "C", "D"] {
            service.createTask(title: title, in: inbox)
        }
        let task = try openTask("B")

        service.toggleDone(task)
        #expect(openTitles(in: inbox) == ["A", "C", "D"])
        service.toggleDone(task)

        #expect(openTitles(in: inbox) == ["A", "B", "C", "D"])
    }

    @Test("uncheck returns the task between its old neighbors after other tasks moved or were added")
    func uncheckAfterOtherChanges() throws {
        for title in ["A", "B", "C", "D"] {
            service.createTask(title: title, in: inbox)
        }
        let task = try openTask("B")
        service.toggleDone(task)

        try service.moveTask(openTask("D"), to: 0)
        service.createTask(title: "E", in: inbox, at: 1)
        #expect(openTitles(in: inbox) == ["D", "E", "A", "C"])
        service.toggleDone(task)

        #expect(openTitles(in: inbox) == ["D", "E", "A", "B", "C"])
    }

    // MARK: - Move

    @Test("moveTask moves a task down and up")
    func moveTaskReorders() throws {
        for title in ["A", "B", "C", "D"] {
            service.createTask(title: title, in: inbox)
        }

        try service.moveTask(openTask("A"), to: 2)
        #expect(openTitles(in: inbox) == ["B", "C", "A", "D"])

        try service.moveTask(openTask("D"), to: 0)
        #expect(openTitles(in: inbox) == ["D", "B", "C", "A"])
        #expect(service.openTasks(in: inbox).map(\.sortIndex) == [0, 1, 2, 3])
    }

    @Test("moveTask puts an index out of range at the nearest end")
    func moveTaskClampsIndex() throws {
        for title in ["A", "B", "C"] {
            service.createTask(title: title, in: inbox)
        }

        try service.moveTask(openTask("A"), to: 99)
        #expect(openTitles(in: inbox) == ["B", "C", "A"])

        try service.moveTask(openTask("A"), to: -1)
        #expect(openTitles(in: inbox) == ["A", "B", "C"])
    }

    // MARK: - Queries

    @Test("openTasks and completedTasks list only the note's own tasks")
    func listsAreScopedToTheNote() {
        let errands = service.createNote(title: "Errands")
        service.createTask(title: "Inbox task", in: inbox)
        let errand = service.createTask(title: "Buy milk", in: errands)
        service.createTask(title: "Post letter", in: errands)
        service.toggleDone(errand)

        #expect(openTitles(in: inbox) == ["Inbox task"])
        #expect(service.completedTasks(in: inbox).isEmpty)
        #expect(openTitles(in: errands) == ["Post letter"])
        #expect(service.completedTasks(in: errands).map(\.title) == ["Buy milk"])
    }

    @Test("completedTasks lists the most recently completed task first")
    func completedTasksNewestFirst() throws {
        for title in ["A", "B", "C"] {
            service.createTask(title: title, in: inbox)
        }

        for title in ["A", "C", "B"] {
            try service.toggleDone(openTask(title))
        }

        #expect(service.completedTasks(in: inbox).map(\.title) == ["B", "C", "A"])
    }

    @Test("actualSeconds sums sessions")
    func actualSecondsSumsSessions() {
        let task = service.createTask(title: "A", in: inbox)
        let otherTask = service.createTask(title: "B", in: inbox)
        #expect(service.actualSeconds(for: task) == 0)

        addSession(to: task, activeSeconds: 60)
        addSession(to: task, activeSeconds: 120.5)
        addSession(to: task, activeSeconds: 300)
        addSession(to: otherTask, activeSeconds: 1000)

        #expect(service.actualSeconds(for: task) == 480.5)
        #expect(service.actualSeconds(for: otherTask) == 1000)
    }

    @Test("A session stores its outcome as text")
    func sessionOutcomeRoundTrips() {
        let session = TimerSession()
        #expect(session.outcome == nil)

        session.outcome = .deleted
        #expect(session.outcomeRaw == "deleted")
        #expect(session.outcome == .deleted)

        session.outcomeRaw = "unknown"
        #expect(session.outcome == nil)
    }

    // MARK: - Helpers

    private func allNotes() throws -> [Note] {
        try store.context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    private func openTitles(in note: Note) -> [String] {
        service.openTasks(in: note).map(\.title)
    }

    /// The Inbox's open task with this title. Titles are unique in these tests.
    private func openTask(_ title: String) throws -> TaskItem {
        try #require(service.openTasks(in: inbox).first { $0.title == title })
    }

    private func addSession(to task: TaskItem, activeSeconds: TimeInterval) {
        let session = TimerSession(activeSeconds: activeSeconds)
        store.context.insert(session)
        session.task = task
    }
}
