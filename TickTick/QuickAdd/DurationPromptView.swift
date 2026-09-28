// Last edited: 2026-09-24 17:58 PT

import SwiftUI

/// The line under the "How long?" field for one input (product decision 7).
/// It is pure, so tests can check it with a fixed time, locale, and time zone.
struct DurationPromptModel: Equatable {
    enum Line: Equatable {
        /// The field is empty or blank, so no line shows.
        case none
        /// The live preview, for example `= 1 h 30 min · ends 3:42 PM`.
        case preview(String)
        /// The quiet hint for text that is not a duration.
        case hint(String)
    }

    static let hintText = "Not a duration"

    /// The typed duration in seconds, or nil when the text is empty or does not parse.
    /// Return starts a timer only when this is not nil.
    let seconds: TimeInterval?
    let line: Line

    /// Reads `text` with the same rules as the popover's `+custom` field.
    init(
        text: String,
        now: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        let entry = CustomExtendEntry(text: text)
        seconds = entry.seconds
        if let seconds = entry.seconds {
            line = .preview(TimeFormatting.preview(seconds: seconds, now: now, locale: locale, timeZone: timeZone))
        } else if entry.isInvalid {
            line = .hint(Self.hintText)
        } else {
            line = .none
        }
    }
}

/// The reusable "How long?" field: a text field with a live preview, and chips that start a timer at once.
///
/// Return starts the timer when the text is a duration, and does nothing otherwise. Esc skips.
/// The view knows no engine, window, or store. It talks only through `onStart` and `onSkip`, so the quick-add
/// panel and the Notes window (TT-9) can both use it. The caller owns `text`, so the input can outlive the view.
struct DurationPromptView: View {
    nonisolated static let chipMinutes = [5, 15, 25, 45, 60]
    static let placeholder = "How long? 25, 1h30, 1:30…"

    @Binding var text: String
    var fontSize: CGFloat = 22
    /// Called with the duration in seconds, after Return on a valid duration or a chip click.
    let onStart: (TimeInterval) -> Void
    /// Called on Esc.
    let onSkip: () -> Void
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Redraws at each new minute, so the "ends" time in the preview stays right.
            TimelineView(.everyMinute) { _ in
                let model = DurationPromptModel(text: text, now: .now)
                VStack(alignment: .leading, spacing: 4) {
                    field(model)
                    previewLine(model.line)
                }
            }
            chips
        }
    }

    private func field(_ model: DurationPromptModel) -> some View {
        TextField(Self.placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: fontSize))
            .focused($fieldHasFocus)
            .task {
                // Focus set at once is lost while the window appears. A short wait makes it stick.
                try? await Task.sleep(for: .milliseconds(50))
                fieldHasFocus = true
            }
            .onSubmit {
                if let seconds = model.seconds {
                    onStart(seconds)
                }
            }
            .onExitCommand(perform: onSkip)
    }

    /// Always one line high, so the chips do not jump when the preview comes and goes.
    private func previewLine(_ line: DurationPromptModel.Line) -> some View {
        Group {
            switch line {
            case .none:
                Text(" ")
            case let .preview(text):
                Text(text)
                    .foregroundStyle(.secondary)
            case let .hint(text):
                Text(text)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(Self.chipMinutes, id: \.self) { minutes in
                Button("\(minutes)m") {
                    onStart(TimeInterval(minutes * 60))
                }
                .buttonBorderShape(.capsule)
                .monospacedDigit()
            }
        }
        .buttonStyle(.bordered)
    }
}
