// Last edited: 2026-09-29 18:35 CDT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// The sidebar queries in `TaskService` and the rules of `NotesSidebarModel`.
@MainActor
struct NoteSidebarTests {
    private let store: ModelStore
    private let service: TaskService
    private let inbox: Note
    private let defaults: TestTimerDefaults

    init() throws {
        defaults = try TestTimerDefaults()
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context)
        inbox = try store.bootstrapInbox()
    }

    private func makeModel() -> NotesSidebarModel {
        NotesSidebarModel(service: service, selectedNoteStore: defaults.makeSelectedNoteStore())
    }

    // MARK: - TaskService

    @Test("sidebarNotes lists the Inbox first, then the notes by sortIndex")
    func sidebarNotesOrder() {
        let work = service.createNote(title: "Work")
        service.createNote(title: "Errands")
        work.sortIndex = 7
        inbox.sortIndex = 9

        #expect(service.sidebarNotes().map(\.title) == ["Inbox", "Errands", "Work"])
    }

    @Test("A new note goes last in the sidebar")
    func newNoteGoesLast() {
        service.createNote(title: "Work")
        service.createNote(title: "Errands")

        #expect(service.sidebarNotes().map(\.title) == ["Inbox", "Work", "Errands"])
    }

    @Test("note(withID:) finds a note, and nil after the note is deleted")
    func noteWithID() throws {
        let work = service.createNote(title: "Work")
        let id = work.id

        #expect(service.note(withID: id) === work)
        try service.deleteNote(work)
        #expect(service.note(withID: id) == nil)
    }

    // MARK: - NotesSidebarModel

    @Test("The Inbox is selected at the start")
    func inboxSelectedAtStart() {
        service.createNote(title: "Work")

        let model = makeModel()

        #expect(model.notes.map(\.title) == ["Inbox", "Work"])
        #expect(model.selectedNote === inbox)
    }

    @Test("A selection is saved, and a new model starts with it")
    func selectionIsSavedAndRestored() {
        let work = service.createNote(title: "Work")
        let model = makeModel()

        model.select(noteID: work.id)

        #expect(defaults.makeSelectedNoteStore().noteID == work.id)
        #expect(makeModel().selectedNote === work)
    }

    @Test("A saved note that is gone selects the Inbox and saves it")
    func staleSavedSelectionFallsBackToInbox() {
        defaults.makeSelectedNoteStore().noteID = UUID()

        let model = makeModel()

        #expect(model.selectedNote === inbox)
        #expect(defaults.makeSelectedNoteStore().noteID == inbox.id)
    }

    @Test("select(noteID:) selects the note, or the Inbox for nil or an unknown ID")
    func selectByID() {
        let work = service.createNote(title: "Work")
        let model = makeModel()

        model.select(noteID: work.id)
        #expect(model.selectedNote === work)
        model.select(noteID: nil)
        #expect(model.selectedNote === inbox)
        model.select(noteID: UUID())
        #expect(model.selectedNote === inbox)
    }

    @Test("select(noteID:) finds a note that was created after the model read the notes")
    func selectFindsANewNote() {
        let model = makeModel()
        let work = service.createNote(title: "Work")

        model.select(noteID: work.id)

        #expect(model.selectedNote === work)
    }

    @Test("A click on no row keeps the selection")
    func clickOnNoRowKeepsSelection() {
        let work = service.createNote(title: "Work")
        let model = makeModel()

        model.selectInList(work.id)
        model.selectInList(nil)

        #expect(model.selectedNote === work)
    }

    @Test("createNote adds New Note last, selects it, and opens its title")
    func createNoteSelectsAndRenames() throws {
        let model = makeModel()

        model.createNote()

        let note = try #require(model.notes.last)
        #expect(model.notes.map(\.title) == ["Inbox", NotesSidebarModel.newNoteTitle])
        #expect(model.selection == note.id)
        #expect(model.renamingID == note.id)
        #expect(model.renameText == NotesSidebarModel.newNoteTitle)
    }

    @Test("commitRename saves the trimmed title, and the title survives a new read")
    func commitRenameSavesTrimmedTitle() {
        let model = makeModel()
        model.createNote()

        model.renameText = "  Groceries \n"
        model.commitRename()

        #expect(model.renamingID == nil)
        let reread = NotesSidebarModel(
            service: TaskService(context: store.context),
            selectedNoteStore: defaults.makeSelectedNoteStore()
        )
        #expect(reread.notes.map(\.title) == ["Inbox", "Groceries"])
    }

    @Test("An empty or blank title keeps the old title", arguments: ["", "   ", "\n"])
    func blankTitleKeepsOldTitle(text: String) {
        let work = service.createNote(title: "Work")
        let model = makeModel()

        model.startRenaming(work)
        model.renameText = text
        model.commitRename()

        #expect(work.title == "Work")
        #expect(model.renamingID == nil)
    }

    @Test("cancelRename closes the field and keeps the old title")
    func cancelRenameKeepsTitle() {
        let model = makeModel()
        model.startRenaming(inbox)

        model.renameText = "Capture"
        model.cancelRename()

        #expect(inbox.title == "Inbox")
        #expect(model.renamingID == nil)
    }

    @Test("Renaming a second note saves the first one")
    func secondRenameSavesTheFirst() {
        let work = service.createNote(title: "Work")
        let model = makeModel()
        model.startRenaming(work)
        model.renameText = "Job"

        model.startRenaming(inbox)

        #expect(work.title == "Job")
        #expect(model.renamingID == inbox.id)
        #expect(model.renameText == "Inbox")
    }

    @Test("The Inbox gets no delete question")
    func inboxHasNoDelete() {
        let model = makeModel()

        model.requestDelete(inbox)

        #expect(model.pendingDelete == nil)
    }

    @Test("Cancel in the delete question keeps the note")
    func cancelDeleteKeepsNote() {
        let work = service.createNote(title: "Work")
        let model = makeModel()

        model.requestDelete(work)
        #expect(model.pendingDelete === work)
        model.cancelDelete()
        model.confirmDelete()

        #expect(model.notes.map(\.title) == ["Inbox", "Work"])
    }

    @Test("Deleting the selected note deletes its tasks and selects the Inbox")
    func deleteSelectedNoteSelectsInbox() throws {
        let work = service.createNote(title: "Work")
        service.createTask(title: "Write report", in: work)
        let model = makeModel()
        model.select(noteID: work.id)

        model.requestDelete(work)
        model.confirmDelete()

        #expect(model.notes.map(\.title) == ["Inbox"])
        #expect(model.selectedNote === inbox)
        #expect(model.pendingDelete == nil)
        #expect(try store.context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
    }

    @Test("Deleting a note that is not selected keeps the selection")
    func deleteOtherNoteKeepsSelection() {
        let work = service.createNote(title: "Work")
        let errands = service.createNote(title: "Errands")
        let model = makeModel()
        model.select(noteID: errands.id)

        model.requestDelete(work)
        model.confirmDelete()

        #expect(model.notes.map(\.title) == ["Inbox", "Errands"])
        #expect(model.selectedNote === errands)
    }
}
