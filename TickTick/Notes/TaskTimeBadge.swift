// Last edited: 2026-09-28 17:15 PT

import SwiftUI

/// The row's time badge: `⏱ 45m est · 52m actual` (product decision 14), with only the parts that exist.
/// While the task's timer runs, the actual time goes up live, at the same moments as the menu bar label.
struct TaskTimeBadge: View {
    let task: TaskItem
    let model: TaskListModel

    var body: some View {
        if let timer = model.activeTimer(for: task) {
            TimelineView(TimerTickSchedule(timer: timer)) { context in
                label(model.timeBadge(for: task, at: context.date))
            }
        } else {
            label(model.timeBadge(for: task, at: .now))
        }
    }

    @ViewBuilder
    private func label(_ text: String?) -> some View {
        if let text {
            HStack(spacing: 3) {
                Image(systemName: "stopwatch")
                Text(text)
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("Estimated time · actual time on the timer")
            .accessibilityElement(children: .combine)
        }
    }
}
