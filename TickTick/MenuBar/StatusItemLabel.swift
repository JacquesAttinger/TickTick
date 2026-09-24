// Last edited: 2026-09-24 15:33 PT

import AppKit

/// Builds the menu bar text for the timer state (decisions 9 and 12):
///
/// - Idle: `⏱` only.
/// - Running: `⏱ Write cover letter · 24:13` in the label color.
/// - Paused: `⏸ Write cover letter · 24:13` in the secondary label color (dimmed).
/// - Overtime: `⏱ Write cover letter · +2:13` in red. It counts up.
///
/// The name is cut to 24 characters. All digits have the same width, so the label does not move while it counts.
enum StatusItemLabel {
    static let timerSymbol = "⏱"
    static let pausedSymbol = "⏸"

    /// The menu bar font size, with monospaced digits.
    static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
    }

    /// The status item title for `timer` (nil when idle) at `now`.
    static func make(for timer: ActiveTimer?, taskName: String, now: Date) -> NSAttributedString {
        NSAttributedString(
            string: text(for: timer, taskName: taskName, now: now),
            attributes: [.font: font, .foregroundColor: color(for: timer)]
        )
    }

    /// The title text. A task with an empty name shows only the symbol and the time.
    static func text(for timer: ActiveTimer?, taskName: String, now: Date) -> String {
        guard let timer else {
            return timerSymbol
        }
        let (symbol, time) = switch timer.phase {
        case .running: (timerSymbol, TimeFormatting.countdown(timer.remaining(at: now)))
        case .paused: (pausedSymbol, TimeFormatting.countdown(timer.remaining(at: now)))
        case .overtime: (timerSymbol, TimeFormatting.overtime(timer.overtime(at: now)))
        }
        let name = TimeFormatting.menuBarName(taskName.trimmingCharacters(in: .whitespacesAndNewlines))
        return name.isEmpty ? "\(symbol) \(time)" : "\(symbol) \(name) · \(time)"
    }

    /// Dynamic colors, so the text follows the menu bar's light or dark look.
    static func color(for timer: ActiveTimer?) -> NSColor {
        switch timer?.phase {
        case .paused: .secondaryLabelColor
        case .overtime: .systemRed
        case .running, nil: .labelColor
        }
    }

    /// The next time after `now` at which the shown time changes, or nil when it does not change (idle or paused).
    /// The countdown rounds up and the overtime rounds down, so both change when the time passes a whole second
    /// before or after the end date. A 1 s refresh that starts here stays in step with the display.
    static func nextChange(for timer: ActiveTimer?, after now: Date) -> Date? {
        guard let timer else {
            return nil
        }
        let wait: TimeInterval
        switch timer.phase {
        case .paused:
            return nil
        case .running:
            let fraction = timer.remaining(at: now).truncatingRemainder(dividingBy: 1)
            wait = fraction > 0 ? fraction : 1
        case .overtime:
            wait = 1 - timer.overtime(at: now).truncatingRemainder(dividingBy: 1)
        }
        return now.addingTimeInterval(wait)
    }
}
