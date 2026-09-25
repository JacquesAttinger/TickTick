// Last edited: 2026-09-24 19:09 PT

import Foundation
import Observation
import os

/// The state behind the Notes window's sidebar: the notes in order, the selected note, the note being renamed,
/// and the note that waits for the delete confirmation.
///
/// Every change goes through `TaskService`. The views only show this state and call these methods, so the tests can
/// check the rules without a window. There is always a selected note: the Inbox when nothing else is selected.
@Observable
@MainActor
final class NotesSidebarModel {
    static let newNoteTitle = "New Note"
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "NotesSidebar")

    private let service: TaskService
    /// The Inbox first, then the other notes by `sortIndex`.
    private(set) var notes: [Note] = []
    /// The ID of the selected note.
    private(set) var selection: UUID?
    /// The ID of the note whose title is an open text field.
    private(set) var renamingID: UUID?
    /// The text in the open title field.
    var renameText = ""
    /// The note that "Delete…" asks about. It is nil when no question shows.
    private(set) var pendingDelete: Note?

    init(service: TaskService) {
        self.service = service
        reload()
    }

    var selectedNote: Note? {
        notes.first { $0.id == selection }
    }

    private var inbox: Note? {
        notes.first(where: \.isInbox)
    }

    /// Reads the notes again. When the selected note is gone, the Inbox is selected.
    func reload() {
        notes = service.sidebarNotes()
        if selectedNote == nil {
            selection = inbox?.id
        }
    }

    /// Selects the note with `id`. When `id` is nil or no note has it, the Inbox is selected.
    func select(noteID id: UUID?) {
        reload()
        selection = notes.first { $0.id == id }?.id ?? inbox?.id
    }

    /// A click in the list. A click on no row (nil) keeps the selection, so a note is always selected.
    func selectInList(_ id: UUID?) {
        guard let id, notes.contains(where: { $0.id == id }) else {
            return
        }
        selection = id
    }

    /// Adds "New Note" after all other notes, selects it, and opens its title for typing (⌘N).
    func createNote() {
        commitRename()
        let note = service.createNote(title: Self.newNoteTitle)
        reload()
        startRenaming(note)
    }

    /// Selects the note and opens its title for typing (a double-click, or "Rename" in the context menu).
    func startRenaming(_ note: Note) {
        commitRename()
        selection = note.id
        renameText = note.title
        renamingID = note.id
    }

    /// Saves the text of the open title field and closes the field (Return, or a click elsewhere).
    /// The title is trimmed. An empty or blank title keeps the old one.
    func commitRename() {
        guard let id = renamingID else {
            return
        }
        renamingID = nil
        guard let note = notes.first(where: { $0.id == id }),
              let title = Self.title(from: renameText),
              title != note.title
        else {
            return
        }
        service.renameNote(note, to: title)
    }

    /// Closes the title field and keeps the old title (Esc).
    func cancelRename() {
        renamingID = nil
    }

    /// Asks before a delete. The Inbox cannot be deleted, so it gets no question.
    func requestDelete(_ note: Note) {
        guard !note.isInbox else {
            return
        }
        pendingDelete = note
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    /// Deletes the note that the question was about, with its tasks. When it was selected, the Inbox is selected.
    func confirmDelete() {
        guard let note = pendingDelete else {
            return
        }
        pendingDelete = nil
        let id = note.id
        if renamingID == id {
            renamingID = nil
        }
        // Take the note out of the state first, so no view reads it after the delete.
        notes.removeAll { $0.id == id }
        if selection == id {
            selection = inbox?.id
        }
        do {
            try service.deleteNote(note)
        } catch {
            Self.logger.error("Deleting a note failed: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    /// The trimmed title, or nil when nothing is left.
    nonisolated static func title(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
