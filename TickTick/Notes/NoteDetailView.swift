// Last edited: 2026-09-24 19:56 PT

import AppKit
import SwiftUI

/// The right side of the Notes window: the selected note's title, its open tasks as rows, and the empty draft row
/// at the bottom. Under the row being timed, it shows "How long?" or the switch question.
///
/// The keyboard focus follows `TaskListFlow.focus`. While the prompt or the question shows, no row has the focus:
/// the prompt's field takes it, and the question answers Return and Esc. A click in a row reports the new focus
/// back to the flow. The parent gives each note a new view (`.id(note.id)`), so each note starts with a new flow.
struct NoteDetailView: View {
    /// The largest width of the prompt and the question, so their buttons stay near the text in a wide window.
    static let inlineMaxWidth: CGFloat = 520
    /// The space between the edge of the prompt's box and its content.
    static let inlinePadding: CGFloat = 12
    private static let inlineID = "inline"

    let note: Note
    @State private var model: TaskListModel
    @FocusState private var focusedRow: TaskListFlow.Row?
    /// The row that the flow (a key press) gave the focus to. Its caret goes to the end of the title.
    @State private var keyboardFocusRow: TaskListFlow.Row?

    init(note: Note, service: TaskService, engine: TimerEngine) {
        self.note = note
        _model = State(initialValue: TaskListModel(noteID: note.id, service: service, engine: engine))
    }

    var body: some View {
        let tasks = model.openTasks(in: note)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(note.title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    rows(tasks)
                        // The checkboxes line up with the title. Only the row highlight reaches past it.
                        .padding(.horizontal, -TaskRowView.horizontalInset)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: tasks.map(\.id), initial: true) { _, ids in
                model.send(.tasksChanged(ids))
            }
            .onChange(of: model.flow.focus) {
                applyFlowFocus(proxy)
            }
            .onChange(of: model.flow.inline) {
                applyFlowFocus(proxy)
            }
            .onChange(of: focusedRow) { old, new in
                reportFocus(from: old, to: new)
            }
        }
    }

    private func rows(_ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tasks, id: \.id) { task in
                TaskRowView(
                    task: task,
                    model: model,
                    focus: $focusedRow,
                    placesCaretAtEnd: keyboardFocusRow == .task(task.id)
                )
                .id(TaskListFlow.Row.task(task.id))
                if model.flow.inline?.taskID == task.id {
                    inlineContent
                        .id(Self.inlineID)
                }
            }
            DraftRowView(model: model, focus: $focusedRow)
                .id(TaskListFlow.Row.draft)
        }
    }

    /// "How long?" or the switch question in a light box. Its text lines up with the row titles above.
    private var inlineContent: some View {
        Group {
            switch model.flow.inline {
            case .prompt:
                DurationPromptView(text: $model.durationText, fontSize: 15) { seconds in
                    model.send(.startRequested(seconds: seconds))
                } onSkip: {
                    model.send(.skipDuration)
                }
            case .confirmSwitch:
                SwitchConfirmationView { now in
                    model.switchMessage(at: now) ?? ""
                } onConfirm: {
                    model.send(.confirmSwitch)
                } onCancel: {
                    model.send(.cancelSwitch)
                }
            case nil:
                EmptyView()
            }
        }
        .padding(Self.inlinePadding)
        .frame(maxWidth: Self.inlineMaxWidth, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, Self.titleOffset - Self.inlinePadding)
        .padding(.vertical, 4)
    }

    /// Where a row's title starts, from the left edge of the row.
    private static var titleOffset: CGFloat {
        TaskRowView.horizontalInset + TaskRowView.iconColumnWidth + TaskRowView.iconSpacing
    }

    /// Moves the keyboard to where the flow says, and scrolls it into view.
    private func applyFlowFocus(_ proxy: ScrollViewProxy) {
        if model.flow.inline == nil {
            // After a click, the focus is already there, and the caret stays where you clicked.
            keyboardFocusRow = focusedRow == model.flow.focus ? nil : model.flow.focus
            focusedRow = model.flow.focus
            withAnimation {
                proxy.scrollTo(model.flow.focus)
            }
        } else {
            // The prompt's field takes the focus by itself. The question needs no field.
            focusedRow = nil
            withAnimation {
                proxy.scrollTo(Self.inlineID)
            }
        }
    }

    /// Tells the flow about focus that moved: a click in a row, or any move that left the draft row.
    private func reportFocus(from old: TaskListFlow.Row?, to new: TaskListFlow.Row?) {
        if old == nil, case .task = new, new != model.flow.focus, !Self.focusCameFromUser {
            // AppKit gives the first text field the focus when the window opens, with the whole title selected, so
            // the first key would replace it. The draft row gets that focus instead.
            focusedRow = .draft
            return
        }
        if new == nil, old == keyboardFocusRow {
            // The focus left the rows, so a later click in that row keeps the caret where you click.
            keyboardFocusRow = nil
        }
        if old == .draft, new != .draft {
            model.send(.draftFocusLost(title: model.draftText))
        }
        if let new {
            model.send(.focusChanged(new))
        }
    }

    /// True when the last event was a click or a key press in this window, not AppKit's own choice. The click on
    /// "Open Notes" that opens the window happens in the popover, so it does not count.
    private static var focusCameFromUser: Bool {
        guard let event = NSApp.currentEvent, event.window != nil, event.window === NSApp.keyWindow else {
            return false
        }
        switch event.type {
        case .keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown,
             .otherMouseUp:
            return true
        default:
            return false
        }
    }
}
