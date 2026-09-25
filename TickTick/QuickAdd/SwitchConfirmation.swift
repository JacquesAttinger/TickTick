// Last edited: 2026-09-24 17:58 PT

import SwiftUI

/// The question before a new timer replaces the active one (product decision 8):
/// `Stop “A” (12 min left) and start “B”?`
enum SwitchConfirmation {
    /// The question for the active `current` timer on the task `currentTitle`, at `now`.
    static func message(current: ActiveTimer, currentTitle: String, newTitle: String, now: Date) -> String {
        "Stop “\(currentTitle)” (\(timeText(current, now: now))) and start “\(newTitle)”?"
    }

    /// `12 min left` while running or paused, and `2 min over` in overtime, where "0 min left" would be false.
    static func timeText(_ timer: ActiveTimer, now: Date) -> String {
        if case .overtime = timer.phase {
            return "\(TimeFormatting.human(timer.overtime(at: now))) over"
        }
        return "\(TimeFormatting.human(timer.remaining(at: now))) left"
    }
}

/// The switch question with "Cancel" (Esc) and "Stop & Start" (Return).
/// The Notes window (TT-9) can use it too. The message is built again every second, so its time stays right.
struct SwitchConfirmationView: View {
    /// The question at a given time, for example from `SwitchConfirmation.message`.
    let message: (Date) -> String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(message(context.date))
                    .font(.title3)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Stop & Start", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }
}
