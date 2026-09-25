// Last edited: 2026-09-24 17:58 PT

import SwiftUI

/// The content of the quick-add panel: step 1 (the task), step 2 ("How long?"), or the switch question.
/// It reports its height, so the panel can fit it and keep its top edge in place.
struct QuickAddView: View {
    static let width: CGFloat = 560
    static let cornerRadius: CGFloat = 18

    let session: QuickAddSession
    /// Called with the content height after each change.
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: Self.width, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                onHeightChange(height)
            }
            .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch session.step {
        case .task, .closed:
            TaskStepView(session: session)
        case .duration:
            DurationStepView(session: session)
        case .confirmSwitch:
            SwitchConfirmationView { now in
                session.switchMessage(at: now) ?? ""
            } onConfirm: {
                session.send(.confirmSwitch)
            } onCancel: {
                session.send(.cancelSwitch)
            }
        }
    }
}

/// Step 1: a large field for the task title. Return saves it, and Esc closes.
private struct TaskStepView: View {
    @Bindable var session: QuickAddSession
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            TextField("New task…", text: $session.taskText)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($fieldHasFocus)
                .task {
                    // Focus set at once is lost while the panel appears. A short wait makes it stick.
                    try? await Task.sleep(for: .milliseconds(50))
                    fieldHasFocus = true
                }
                .onSubmit {
                    session.send(.submitTask(session.taskText))
                }
                .onExitCommand {
                    session.send(.escapeOnTask)
                }
        }
    }
}

/// Step 2: the saved task on top, then the "How long?" field and its chips.
private struct DurationStepView: View {
    @Bindable var session: QuickAddSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(session.flow.taskTitle ?? "", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            DurationPromptView(text: $session.durationText) { seconds in
                session.send(.startRequested(seconds: seconds))
            } onSkip: {
                session.send(.skipDuration)
            }
            Text("Saved in Inbox. Esc keeps it without a timer.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
