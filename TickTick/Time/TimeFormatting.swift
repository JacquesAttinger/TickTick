// Last edited: 2026-09-24 15:40 PT

import Foundation

/// Turns seconds and dates into the text that the menu bar, the popover, and the quick-add preview show.
enum TimeFormatting {
    /// The longest task name, in characters, that the menu bar shows without a cut.
    static let menuBarNameLimit = 24

    /// Time left: `m:ss` under one hour (`24:13`), and `h:mm:ss` from one hour (`1:02:03`).
    /// A part of a second rounds up, so the text shows `0:00` only when the time is up.
    /// Negative input shows `0:00`.
    static func countdown(_ seconds: TimeInterval) -> String {
        colonText(wholeNumber(seconds.rounded(.up)))
    }

    /// Time past zero: `+2:13` under one hour, and `+1:02:03` from one hour.
    /// A part of a second rounds down, so the count starts at `+0:00`.
    static func overtime(_ seconds: TimeInterval) -> String {
        "+" + colonText(wholeNumber(seconds.rounded(.down)))
    }

    /// A duration in whole minutes: `45 min`, `1 h 30 min`, or `2 h`.
    /// It rounds to the nearest minute and never shows less than `1 min`.
    static func human(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(1, wholeNumber((seconds / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(minutes) min"
        }
    }

    /// A short time of day in the style of the locale: `3:42 PM` (en_US) or `15:42` (de_DE).
    /// en_US puts a narrow no-break space (U+202F), not a normal space, before `PM`.
    static func clock(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
    }

    /// A short date: the weekday, the day, and the month, for example `Tue 22 Sep`.
    /// The names come from the locale, and the order is fixed.
    static func day(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(weekday: .abbreviated) \(day: .defaultDigits) \(month: .abbreviated)",
            locale: locale,
            timeZone: timeZone,
            calendar: Calendar(identifier: .gregorian)
        )
        return date.formatted(style)
    }

    /// The quick-add live preview, for example `= 1 h 30 min · ends 3:42 PM`.
    /// The end time is `now + seconds`.
    static func preview(
        seconds: TimeInterval,
        now: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let end = clock(now.addingTimeInterval(seconds), locale: locale, timeZone: timeZone)
        return "= \(human(seconds)) · ends \(end)"
    }

    /// The task name for the menu bar. A name of 24 characters or fewer does not change.
    /// A longer name keeps its first 24 characters, without trailing whitespace, and gets `…`.
    /// It counts `Character`s, so the cut never splits an emoji.
    static func menuBarName(_ name: String) -> String {
        guard name.count > menuBarNameLimit else { return name }
        var cut = name.prefix(menuBarNameLimit)
        while cut.last?.isWhitespace == true {
            cut.removeLast()
        }
        return String(cut) + "…"
    }

    /// `m:ss` under one hour, and `h:mm:ss` from one hour.
    private static func colonText(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = totalSeconds / 60 % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// A whole number of 0 or more. Negative, NaN, and infinite input give 0.
    private static func wholeNumber(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 0 }
        return Int(value)
    }
}
