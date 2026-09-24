// Last edited: 2026-09-24 16:43 PT

import AppKit
import SwiftUI

/// The popover under the menu bar item: the active timer with its controls, or "No timer running".
/// The footer with "Quit TickTick" is always there, because the app often has no Dock icon.
struct TimerPopoverView: View {
    static let width: CGFloat = 300

    let engine: TimerEngine
    let clock: PopoverClock
    /// A new value clears the view's own state, such as a half-typed custom time.
    var presentationID = 0
    /// Makes the popover take key presses. The "+custom" field calls it before it takes focus.
    var prepareForTyping: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let model {
                    ActiveTimerView(model: model, engine: engine, prepareForTyping: prepareForTyping)
                } else {
                    IdleTimerView()
                }
            }
            .padding(16)
            Divider()
            PopoverFooter()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: Self.width)
        .id(presentationID)
    }

    private var model: TimerPopoverModel? {
        guard let timer = engine.activeTimer else {
            return nil
        }
        let task = engine.activeTask
        return TimerPopoverModel(
            timer: timer,
            taskTitle: task?.title ?? "",
            noteTitle: task?.note?.title ?? "",
            estimateSeconds: task?.estimateSeconds,
            now: clock.now
        )
    }
}

/// The active timer: task, note, time, progress, times of day, and the buttons.
private struct ActiveTimerView: View {
    let model: TimerPopoverModel
    let engine: TimerEngine
    let prepareForTyping: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            timeAndProgress
            VStack(alignment: .leading, spacing: 2) {
                Text(model.scheduleText)
                Text(model.estimateText)
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            ExtendControls(engine: engine, prepareForTyping: prepareForTyping)
            actionButtons
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.taskTitle)
                .font(.headline)
                .lineLimit(2)
            HStack {
                Text(model.noteTitle)
                    .lineLimit(1)
                Spacer()
                // TT-8 makes this open the note in the Notes window.
                Button("Open ↗") {}
                    .buttonStyle(.link)
                    .disabled(true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var timeAndProgress: some View {
        VStack(spacing: 6) {
            Text(model.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.timeText)
                .font(.system(size: 40, weight: .medium).monospacedDigit())
                .foregroundStyle(timeStyle)
            HStack(spacing: 8) {
                ProgressView(value: model.progress)
                    .tint(barColor)
                Text(model.percentText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Dimmed while paused, like the label, and red in overtime.
    private var barColor: Color {
        switch model.phase {
        case .running: .accentColor
        case .paused: .gray
        case .overtime: .red
        }
    }

    private var timeStyle: AnyShapeStyle {
        switch model.phase {
        case .running: AnyShapeStyle(.primary)
        case .paused: AnyShapeStyle(.secondary)
        case .overtime: AnyShapeStyle(.red)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if model.phase == .paused {
                WideButton("Resume") { engine.resume() }
            } else {
                // Overtime cannot pause: it ends with Done, an extension, or Stop (decision 12).
                WideButton("Pause") { engine.pause() }
                    .disabled(model.phase == .overtime)
            }
            WideButton("Stop") { engine.stop() }
            WideButton("Done") { engine.done() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
    }
}

/// A button that shares the width of its row with the other wide buttons.
struct WideButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
    }
}

/// No active timer.
private struct IdleTimerView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("No timer running")
                .font(.headline)
            // TT-7 adds this global shortcut.
            Text("New task: ⌃⌥Space")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

/// Links to the other windows, and Quit.
private struct PopoverFooter: View {
    var body: some View {
        HStack(spacing: 14) {
            // TT-8 makes this open the Notes window.
            Button("Open Notes") {}
                .disabled(true)
            // TT-11 makes this open the Settings window.
            Button("Settings…") {}
                .disabled(true)
            Spacer()
            Button("Quit TickTick") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}
