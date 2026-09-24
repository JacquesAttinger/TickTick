// Last edited: 2026-09-24 14:57 PT

import Foundation

/// Reads a typed duration, such as `25`, `90 min`, `1h30`, `1.5h`, or `1:30`, and returns it in seconds.
///
/// A bare number is minutes. Case and extra whitespace do not matter.
/// The result is whole seconds, more than 0 and at most 24 hours. Any other input gives `nil`.
enum DurationParser {
    /// The longest duration that `parse(_:)` accepts: 24 hours.
    static let maximumSeconds: TimeInterval = 24 * 3600

    static func parse(_ input: String) -> TimeInterval? {
        let text = normalized(input)
        guard let total = colonSeconds(text) ?? hourSeconds(text) ?? minuteSeconds(text) else {
            return nil
        }
        let seconds = total.rounded()
        guard seconds > 0, seconds <= maximumSeconds else { return nil }
        return seconds
    }

    /// Lowercases, trims, and collapses each run of inner whitespace to one space.
    private static func normalized(_ input: String) -> String {
        input.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// `h:mm`, for example `1:30`. The minutes must be `00` to `59`.
    private static func colonSeconds(_ text: String) -> TimeInterval? {
        guard let match = text.wholeMatch(of: /(\d{1,2}):([0-5]\d)/.asciiOnlyDigits()),
              let hours = Double(match.1),
              let minutes = Double(match.2)
        else { return nil }
        return hours * 3600 + minutes * 60
    }

    /// Hours with an hour unit, then optional whole minutes: `1h`, `1.5h`, `1h30`, `1 hr 30 min`.
    private static func hourSeconds(_ text: String) -> TimeInterval? {
        let pattern = /(\d+(?:\.\d+)?) ?(?:hours|hour|hrs|hr|h)(?: ?(\d+) ?(?:minutes|minute|mins|min|m)?)?/
        guard let match = text.wholeMatch(of: pattern.asciiOnlyDigits()),
              let hours = Double(match.1)
        else { return nil }
        let minutes = match.2.flatMap { Double($0) } ?? 0
        return hours * 3600 + minutes * 60
    }

    /// Whole minutes with an optional minute unit: `25`, `25m`, `90 min`.
    private static func minuteSeconds(_ text: String) -> TimeInterval? {
        guard let match = text.wholeMatch(of: /(\d+) ?(?:minutes|minute|mins|min|m)?/.asciiOnlyDigits()),
              let minutes = Double(match.1)
        else { return nil }
        return minutes * 60
    }
}
