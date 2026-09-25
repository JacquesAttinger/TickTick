// Last edited: 2026-09-24 18:40 PT

import SwiftUI

/// The content of the quick-add panel: step 1 (the task), step 2 ("How long?"), or the switch question.
/// It reports its height, so the panel can fit it and keep its top edge in place.
struct QuickAddView: View {
    static let width: CGFloat = 560
    static let cornerRadius: CGFloat = 18
    static let fieldFontSize: CGFloat = 22
    /// The icon column on the left of every step, and the gap after it.
    static let iconColumnWidth: CGFloat = 26
    static let iconSpacing: CGFloat = 12

    let session: QuickAddSession
    /// Called with the content height after each change.
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: Self.width, alignment: .leading)
            // Thick, so the text stays readable over a bright window behind the panel.
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
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
        case .task:
            TaskStepView(session: session)
        case .duration:
            DurationStepView(session: session)
        case .confirmSwitch:
            IconRow(systemImage: "arrow.left.arrow.right", iconSize: 17) {
                SwitchConfirmationView { now in
                    session.switchMessage(at: now) ?? ""
                } onConfirm: {
                    session.send(.confirmSwitch)
                } onCancel: {
                    session.send(.cancelSwitch)
                }
            }
        case .closed:
            EmptyView()
        }
    }
}

/// A row with an icon in a fixed column, so the text of every step starts at the same left edge.
private struct IconRow<Content: View>: View {
    let systemImage: String
    var iconSize: CGFloat = QuickAddView.fieldFontSize
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: QuickAddView.iconSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(.secondary)
                .frame(width: QuickAddView.iconColumnWidth)
            content
        }
    }
}

/// Step 1: a large field for the task title. Return saves it, and Esc closes.
private struct TaskStepView: View {
    @Bindable var session: QuickAddSession
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        IconRow(systemImage: "timer") {
            TextField("New task…", text: $session.taskText)
                .textFieldStyle(.plain)
                .font(.system(size: QuickAddView.fieldFontSize))
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
            IconRow(systemImage: "checkmark.circle.fill", iconSize: 13) {
                Text(session.flow.taskTitle ?? "")
                    .lineLimit(1)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            IconRow(systemImage: "hourglass") {
                VStack(alignment: .leading, spacing: 10) {
                    DurationPromptView(text: $session.durationText, fontSize: QuickAddView.fieldFontSize) { seconds in
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
    }
}
