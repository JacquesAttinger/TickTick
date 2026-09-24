// Last edited: 2026-09-24 14:58 PT

import Foundation
import os
import SwiftData

enum TaskServiceError: Error, Equatable {
    /// The Inbox can be renamed, but it cannot be deleted.
    case cannotDeleteInbox
}

/// Holds every rule for notes and tasks. Views and the timer engine change data only through this service.
///
/// Each operation saves at once. Only `deleteNote` throws. If a fetch or a save fails, the service logs
/// the error, and SwiftData's autosave tries the save again later.
@MainActor
final class TaskService {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "TaskService")

    let context: ModelContext
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
        context.delete(note)
        save()
    }

    // MARK: - Storage

    private func lastNoteSortIndex() -> Int {
        var descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first?.sortIndex ?? -1
        } catch {
            Self.logger.error("Fetching notes failed: \(error.localizedDescription, privacy: .public)")
            return -1
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
