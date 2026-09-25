// Last edited: 2026-09-24 14:57 PT

import Foundation
import Testing
@testable import TickTick

struct DurationParserTests {
    @Test(arguments: [
        // Bare numbers and minute units.
        ("25", 1500),
        ("25m", 1500),
        ("90 min", 5400),
        ("90min", 5400),
        ("45 mins", 2700),
        ("1 minute", 60),
        ("1440", 86400),
        // Hours, alone or with minutes.
        ("1h", 3600),
        ("1h30", 5400),
        ("1h 30m", 5400),
        ("1hr 30mins", 5400),
        ("1 hour 30 minutes", 5400),
        ("2 hours", 7200),
        ("1.5h", 5400),
        ("0.5h", 1800),
        ("1h 90m", 9000),
        ("24h", 86400),
        // Colon form is hours:minutes.
        ("1:30", 5400),
        ("01:30", 5400),
        ("0:05", 300),
        ("24:00", 86400),
        // Case and whitespace do not matter.
        (" 25 M ", 1500),
        ("1H30", 5400),
        ("\t25\n", 1500),
        ("1  h   30  m", 5400),
        // Decimal hours round to whole seconds.
        ("0.01h", 36),
        ("0.001h", 4),
    ] as [(String, TimeInterval)])
    func parsesValidInput(input: String, seconds: TimeInterval) {
        #expect(DurationParser.parse(input) == seconds)
    }

    @Test(arguments: [
        // Empty.
        "", "   ",
        // Zero, negative, or over 24 hours.
        "0", "0m", "0:00", "-5", "25h", "24h 1m", "24:01", "1441", "25 h 30", "0.0001h",
        // Bad colon form.
        ":30", "1:75", "1:5", "100:00",
        // Not a duration.
        "abc", "h", "m", "1h abc", "1h30s", "30s", "+25",
        // Decimal minutes, a decimal comma, and non-ASCII digits.
        "1.5", "1.5m", "1h 1.5m", "1,5h", ".5h", "٢٥",
    ])
    func rejectsInvalidInput(input: String) {
        #expect(DurationParser.parse(input) == nil)
    }
}
