// Last edited: 2026-09-24 16:43 PT

import AppKit
import SwiftUI

/// The `+1m`, `+5m`, `+10m`, and `+custom` buttons. `+custom` turns the row into a field for a typed duration,
/// read by `DurationParser` (`2`, `90m`, `1h30`, `1:30`). Return adds the time. Esc or ✕ cancels, and closing
/// the popover cancels too. A value that does not parse shows in red, and the Add button is off.
struct ExtendControls: View {
    static let presetMinutes = [1, 5, 10]

    let engine: TimerEngine
    /// Makes the popover take key presses. It runs before the field takes focus.
    let prepareForTyping: () -> Void
    @State private var isEditing = false
    @State private var text = ""
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                customField
            } else {
                presetButtons
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder private var presetButtons: some View {
        ForEach(Self.presetMinutes, id: \.self) { minutes in
            WideButton("+\(minutes)m") { engine.extend(seconds: TimeInterval(minutes * 60)) }
        }
        // Its own width, so the word is never cut. The presets share the rest.
        Button("+custom") {
            prepareForTyping()
            isEditing = true
        }
        .fixedSize()
    }

    @ViewBuilder private var customField: some View {
        let entry = CustomExtendEntry(text: text)
        TextField("Add time, like 2m or 1h30", text: $text)
            .textFieldStyle(.roundedBorder)
            .foregroundStyle(entry.isInvalid ? .red : .primary)
            .focused($fieldHasFocus)
            .task {
                try? await Task.sleep(for: .milliseconds(50))
                fieldHasFocus = true
            }
            .onSubmit { add(entry) }
            .onExitCommand { cancel() }
        Button("Add") { add(entry) }
            .disabled(entry.seconds == nil)
        Button {
            cancel()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Cancel")
        .accessibilityLabel("Cancel")
    }

    private func add(_ entry: CustomExtendEntry) {
        guard let seconds = entry.seconds else {
            NSSound.beep()
            return
        }
        engine.extend(seconds: seconds)
        cancel()
    }

    private func cancel() {
        text = ""
        isEditing = false
    }
}

/// What the `+custom` field holds: a duration, nothing yet, or text that is not a duration.
struct CustomExtendEntry: Equatable {
    /// The typed duration in seconds, or nil when the text is empty or does not parse.
    let seconds: TimeInterval?
    /// True when there is text and it does not parse. Empty text is not an error yet.
    let isInvalid: Bool

    init(text: String) {
        seconds = DurationParser.parse(text)
        isInvalid = seconds == nil && !text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
