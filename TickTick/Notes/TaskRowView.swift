// Last edited: 2026-09-24 20:16 PT

import SwiftUI

/// One open task in the Notes window: a checkbox, the title as a text field, the live timer of the running task,
/// and ▶, which shows on hover and on the row with the keyboard focus.
///
/// Return or a click elsewhere saves the title, and Esc keeps the old title. An emptied title keeps the old one
/// too. ⌘↩ is ▶ and ⇧⌘C checks the task, both on the row with the focus. "Delete" is in the right-click menu
/// (`TaskRowMenu`).
struct TaskRowView: View {
    /// The column of the checkbox and of the draft row's `+`, so every title starts at the same left edge.
    static let iconColumnWidth: CGFloat = 20
    static let iconSpacing: CGFloat = 8
    /// The space between the row's edge and its content. The highlight of a row reaches this far past the content.
    static let horizontalInset: CGFloat = 8
    static let verticalInset: CGFloat = 5

    let task: TaskItem
    let model: TaskListModel
    let focus: FocusState<TaskListFlow.Row?>.Binding
    /// True when the keyboard (↑, ↓, Return, or ⌫) moves the focus to this row, not a click.
    let placesCaretAtEnd: Bool
    @State private var text: String
    @State private var selection: TextSelection?
    @State private var isHovered = false

    init(
        task: TaskItem,
        model: TaskListModel,
        focus: FocusState<TaskListFlow.Row?>.Binding,
        placesCaretAtEnd: Bool
    ) {
        self.task = task
        self.model = model
        self.focus = focus
        self.placesCaretAtEnd = placesCaretAtEnd
        _text = State(initialValue: task.title)
    }

    private var row: TaskListFlow.Row {
        .task(task.id)
    }

    private var hasFocus: Bool {
        focus.wrappedValue == row
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.iconSpacing) {
            checkbox
            titleField
            if let timer = model.activeTimer(for: task) {
                RunningTimerBadge(timer: timer)
            }
            playButton
        }
        .taskRowChrome(hasFocus: hasFocus, isHovered: isHovered)
        .overlay {
            TaskRowMenu(isEditing: hasFocus) { model.delete(task) }
        }
        .onHover { isHovered = $0 }
        .accessibilityAction(named: "Delete") { model.delete(task) }
        .onChange(of: hasFocus) { _, focused in
            if focused, placesCaretAtEnd {
                placeCaretAtEnd()
            } else if !focused {
                commit()
            }
        }
        .onChange(of: task.title) { _, title in
            if !hasFocus {
                text = title
            }
        }
    }

    private var checkbox: some View {
        Button {
            model.toggleDone(task)
        } label: {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(task.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: Self.iconColumnWidth, height: Self.iconColumnWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(hasFocus ? ShortcutCatalog.markDoneKeys : nil)
        .help("Mark as done (\(ShortcutCatalog.markDone.keysText))")
        .accessibilityLabel("Mark as done")
    }

    /// One line. A long title ends in "…", and while you edit it, it scrolls in its line like any Mac text field.
    /// (A title that wrapped while editing made the row clip its second line.)
    private var titleField: some View {
        TextField("Task", text: $text, selection: $selection, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .truncationMode(.tail)
            .focused(focus, equals: row)
            .onSubmit {
                model.send(.submitRow(id: task.id, title: text))
            }
            .onExitCommand {
                text = task.title
                selection = TextSelection(insertionPoint: text.endIndex)
            }
            .taskRowKeys(
                model: model,
                isEmpty: { text.isEmpty },
                onDeleteEmpty: { model.send(.deleteBackwardOnEmpty(id: task.id)) }
            )
    }

    private var playButton: some View {
        let isShown = isHovered || hasFocus
        return Button {
            model.send(.playTapped(id: task.id))
        } label: {
            Image(systemName: "play.fill")
                .foregroundStyle(.secondary)
                .frame(width: Self.iconColumnWidth, height: Self.iconColumnWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(hasFocus ? ShortcutCatalog.startTimerKeys : nil)
        .help("Start a timer (\(ShortcutCatalog.startTimer.keysText))")
        .accessibilityLabel("Start a timer")
        // Hidden, not removed, so the title does not get wider and narrower as the pointer moves.
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
    }

    /// A text field selects all its text when it gets the focus. After a move by the keyboard, the caret goes to
    /// the end instead, so the next key edits the title and does not replace it. After a click, the caret stays
    /// where you clicked.
    private func placeCaretAtEnd() {
        Task { @MainActor in
            // The field selects all its text a moment after it gets the focus, so the caret moves after that.
            try? await Task.sleep(for: .milliseconds(50))
            if hasFocus {
                selection = TextSelection(insertionPoint: text.endIndex)
            }
        }
    }

    /// Saves the title when the row loses the focus. An emptied title shows the old one again.
    private func commit() {
        // A deleted task must not be read any more: ⌫ takes it out of the flow, and a delete detaches it.
        guard model.flow.rows.contains(task.id), task.modelContext != nil else {
            return
        }
        model.send(.rowFocusLost(id: task.id, title: text))
        if NotesSidebarModel.title(from: text) == nil {
            text = task.title
        }
    }
}

/// The empty row at the bottom of every note. Return saves a new task from it and opens "How long?".
struct DraftRowView: View {
    static let placeholder = "New task"

    @Bindable var model: TaskListModel
    let focus: FocusState<TaskListFlow.Row?>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TaskRowView.iconSpacing) {
            Image(systemName: "plus")
                .imageScale(.large)
                .foregroundStyle(.tertiary)
                .frame(width: TaskRowView.iconColumnWidth, height: TaskRowView.iconColumnWidth)
            TextField(Self.placeholder, text: $model.draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .truncationMode(.tail)
                .focused(focus, equals: .draft)
                .onSubmit {
                    model.send(.submitDraft(title: model.draftText))
                }
                .taskRowKeys(
                    model: model,
                    isEmpty: { model.draftText.isEmpty },
                    onDeleteEmpty: { model.send(.deleteBackwardOnEmptyDraft) }
                )
        }
        .taskRowChrome(hasFocus: focus.wrappedValue == .draft, isHovered: false)
    }
}

/// The live time of the running task: `24:13`, dimmed `24:13` while paused, and red `+2:13` in overtime.
/// It changes at the same moments as the menu bar label. The timer icon pulses while the time counts (down, or up
/// in overtime), unless Reduce Motion is on.
struct RunningTimerBadge: View {
    let timer: ActiveTimer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(TimerTickSchedule(timer: timer)) { context in
            let model = TimerPopoverModel(
                timer: timer,
                taskTitle: "",
                noteTitle: "",
                estimateSeconds: nil,
                now: context.date
            )
            HStack(spacing: 4) {
                Image(systemName: model.phase == .paused ? "pause.circle" : "timer")
                    .symbolEffect(.pulse, options: .repeating, isActive: model.phase != .paused && !reduceMotion)
                Text(model.timeText)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(style(for: model.phase))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.caption) \(model.timeText)")
        }
        .fixedSize()
    }

    private func style(for phase: TimerPopoverModel.Phase) -> AnyShapeStyle {
        switch phase {
        case .running: AnyShapeStyle(.tint)
        case .paused: AnyShapeStyle(.secondary)
        case .overtime: AnyShapeStyle(.red)
        }
    }
}

/// Redraws just after the shown second changes, like the menu bar label, so the row and the label never show
/// different seconds. A paused timer does not change, so it has no later entries.
struct TimerTickSchedule: TimelineSchedule {
    /// The same short delay as the label's refresh, so the rounding lands on the new second.
    static let delay: TimeInterval = 0.02

    let timer: ActiveTimer

    func entries(from startDate: Date, mode _: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        let first = StatusItemLabel.nextChange(for: timer, after: startDate)?.addingTimeInterval(Self.delay)
        return sequence(first: startDate) { date in
            date == startDate ? first : date.addingTimeInterval(1)
        }
    }
}

extension View {
    /// The padding and the highlight of a task row: a gray box on the row with the focus, a lighter one on hover.
    func taskRowChrome(hasFocus: Bool, isHovered: Bool) -> some View {
        padding(.horizontal, TaskRowView.horizontalInset)
            .padding(.vertical, TaskRowView.verticalInset)
            .background(
                .quaternary.opacity(hasFocus ? 1 : isHovered ? 0.5 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
    }

    /// ↑ and ↓ move to the row above and below. ⌫ in an empty field runs `onDeleteEmpty`.
    func taskRowKeys(
        model: TaskListModel,
        isEmpty: @escaping () -> Bool,
        onDeleteEmpty: @escaping () -> Void
    ) -> some View {
        onKeyPress(.upArrow) {
            model.send(.moveUp)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.send(.moveDown)
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            // In a text field, the ⌫ key arrives as U+007F, and no named `KeyEquivalent` matches it.
            guard press.key == .delete || press.key.character == "\u{7F}", isEmpty() else {
                return .ignored
            }
            onDeleteEmpty()
            return .handled
        }
    }
}
