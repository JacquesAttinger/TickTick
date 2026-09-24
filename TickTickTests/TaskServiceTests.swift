// Last edited: 2026-09-24 14:58 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// Returns a time one second later on each call, so every created or completed item has a clear order.
@MainActor
final class SteppingClock {
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

    // MARK: - Helpers

    private func allNotes() throws -> [Note] {
        try store.context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.sortIndex)]))
    }

    private func addSession(to task: TaskItem, activeSeconds: TimeInterval) {
        let session = TimerSession(activeSeconds: activeSeconds)
        store.context.insert(session)
        session.task = task
    }
}
