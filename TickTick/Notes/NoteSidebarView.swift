// Last edited: 2026-09-24 19:09 PT

import SwiftUI

/// The note list of the Notes window: the Inbox first, then the other notes.
///
/// ⌘N or "New Note" adds a note and opens its title for typing. A double-click or "Rename" opens the title of a note.
/// "Delete…" in the context menu asks first. The Inbox has no "Delete…".
struct NoteSidebarView: View {
    let model: NotesSidebarModel

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selection) {
                ForEach(model.notes, id: \.id) { note in
                    NoteRow(note: note, model: model)
                        .tag(note.id)
                        .id(note.id)
                }
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let note = note(in: ids) {
                    contextMenu(for: note)
                }
            } primaryAction: { ids in
                if let note = note(in: ids) {
                    model.startRenaming(note)
                }
            }
            .onChange(of: model.renamingID) { _, id in
                if let id {
                    proxy.scrollTo(id)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            newNoteButton
        }
        .confirmationDialog(
            deleteQuestion,
            isPresented: isAskingToDelete,
            titleVisibility: .visible,
            presenting: model.pendingDelete
        ) { _ in
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.cancelDelete() }
        } message: { _ in
            Text("Its tasks are deleted too.")
        }
    }

    /// A click on no row keeps the selection, so a note is always selected.
    private var selection: Binding<UUID?> {
        Binding {
            model.selection
        } set: { id in
            model.selectInList(id)
        }
    }

    private var isAskingToDelete: Binding<Bool> {
        Binding {
            model.pendingDelete != nil
        } set: { isPresented in
            if !isPresented {
                model.cancelDelete()
            }
        }
    }

    private var deleteQuestion: String {
        "Delete “\(model.pendingDelete?.title ?? "")”?"
    }

    /// The icon and the text line up with the icons and titles of the rows above.
    private var newNoteButton: some View {
        HStack {
            Button {
                model.createNote()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .frame(width: 20)
                    Text("New Note")
                }
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n", modifiers: .command)
            .help("New Note (⌘N)")
            Spacer()
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    /// The note of a right-click or a double-click. It has one ID, or none on empty space.
    private func note(in ids: Set<UUID>) -> Note? {
        guard ids.count == 1, let id = ids.first else {
            return nil
        }
        return model.notes.first { $0.id == id }
    }

    @ViewBuilder private func contextMenu(for note: Note) -> some View {
        Button("Rename") { model.startRenaming(note) }
        if !note.isInbox {
            Divider()
            Button("Delete…", role: .destructive) { model.requestDelete(note) }
        }
    }
}

/// One note in the list: an icon and the title, or a text field while the note is renamed.
private struct NoteRow: View {
    let note: Note
    @Bindable var model: NotesSidebarModel
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        Label {
            if model.renamingID == note.id {
                titleField
            } else {
                Text(note.title)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: note.isInbox ? "tray" : "list.bullet")
        }
    }

    /// Return or a click elsewhere saves the title. Esc keeps the old title.
    ///
    /// The field has its own text colors: on the blue selected row, a system field showed black text on dark blue.
    /// Its box reaches a little past the text on each side, so the text stays in line with the other titles.
    private var titleField: some View {
        TextField("Note name", text: $model.renameText)
            .textFieldStyle(.plain)
            .foregroundStyle(Color(nsColor: .textColor))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, -4)
            .focused($fieldHasFocus)
            .onSubmit { model.commitRename() }
            .onExitCommand { model.cancelRename() }
            .onChange(of: fieldHasFocus) { _, hasFocus in
                if !hasFocus {
                    model.commitRename()
                }
            }
            .task {
                // Focus set at once is lost while the row appears, so it waits a moment.
                try? await Task.sleep(for: .milliseconds(50))
                fieldHasFocus = true
            }
    }
}
