// Last edited: 2026-09-24 19:09 PT

import SwiftUI

/// The right side of the Notes window: the selected note's title and its open tasks.
/// The tasks are read-only text until TT-9 replaces the list with task rows (checkbox, editable title, ▶).
struct NoteDetailView: View {
    let note: Note
    let openTasks: [TaskItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(note.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if openTasks.isEmpty {
                    Text("No tasks yet")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(openTasks, id: \.id) { task in
                            Label(task.title, systemImage: "circle")
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
