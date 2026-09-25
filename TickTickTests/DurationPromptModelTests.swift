// Last edited: 2026-09-24 17:58 PT

import Foundation
import Testing
@testable import TickTick

struct DurationPromptModelTests {
    /// en_US puts this narrow no-break space (U+202F) between the time and `AM` or `PM`.
    private let narrowSpace = "\u{202F}"
    private let locale = Locale(identifier: "en_US")
    private let timeZone: TimeZone
    /// 2:12 PM in Los Angeles.
    private let now: Date

    init() throws {
        timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        now = try Date("2026-09-24T14:12:00-07:00", strategy: .iso8601)
    }

    private func model(_ text: String) -> DurationPromptModel {
        DurationPromptModel(text: text, now: now, locale: locale, timeZone: timeZone)
    }

    @Test("An empty or blank field shows no line and cannot start", arguments: ["", "   "])
    func emptyInput(text: String) {
        let model = model(text)

        #expect(model.seconds == nil)
        #expect(model.line == .none)
    }

    @Test("25 shows its preview with the end time")
    func minutesInput() {
        let model = model("25")

        #expect(model.seconds == 1500)
        #expect(model.line == .preview("= 25 min · ends 2:37\(narrowSpace)PM"))
    }

    @Test("Every way to write 90 minutes shows the same preview", arguments: ["1h30", "1:30", "90 min", " 1.5h "])
    func hoursInput(text: String) {
        let model = model(text)

        #expect(model.seconds == 5400)
        #expect(model.line == .preview("= 1 h 30 min · ends 3:42\(narrowSpace)PM"))
    }

    @Test("Text that is not a duration shows the quiet hint and cannot start", arguments: ["abc", "25h", "0"])
    func invalidInput(text: String) {
        let model = model(text)

        #expect(model.seconds == nil)
        #expect(model.line == .hint("Not a duration"))
    }

    @Test("The chips are 5, 15, 25, 45, and 60 minutes")
    func chips() {
        #expect(DurationPromptView.chipMinutes == [5, 15, 25, 45, 60])
    }
}
