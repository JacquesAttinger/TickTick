// Last edited: 2026-09-28 16:45 PT

import Foundation
import Testing
@testable import TickTick

struct TimeFormattingTests {
    /// en_US puts this narrow no-break space (U+202F) between the time and `AM` or `PM`.
    private let narrowSpace = "\u{202F}"
    private let locale = Locale(identifier: "en_US")
    private let timeZone: TimeZone
    /// 3:42 PM in Los Angeles.
    private let now: Date

    init() throws {
        timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        now = try Date("2026-09-24T15:42:00-07:00", strategy: .iso8601)
    }

    // MARK: - countdown and overtime

    @Test(arguments: [
        (0, "0:00"),
        (59, "0:59"),
        (60, "1:00"),
        (1453, "24:13"),
        (3599, "59:59"),
        (3600, "1:00:00"),
        (3723, "1:02:03"),
        (36000, "10:00:00"),
        // A part of a second rounds up. Negative input shows 0:00.
        (1452.2, "24:13"),
        (0.4, "0:01"),
        (-3, "0:00"),
    ] as [(TimeInterval, String)])
    func countdown(seconds: TimeInterval, text: String) {
        #expect(TimeFormatting.countdown(seconds) == text)
    }

    @Test(arguments: [
        (0, "+0:00"),
        (133, "+2:13"),
        (3723, "+1:02:03"),
        // A part of a second rounds down.
        (133.9, "+2:13"),
        (-1, "+0:00"),
    ] as [(TimeInterval, String)])
    func overtime(seconds: TimeInterval, text: String) {
        #expect(TimeFormatting.overtime(seconds) == text)
    }

    // MARK: - human

    @Test(arguments: [
        (2700, "45 min"),
        (5400, "1 h 30 min"),
        (7200, "2 h"),
        (86400, "24 h"),
        // Rounds to the nearest minute, and never shows less than 1 min.
        (5429, "1 h 30 min"),
        (5431, "1 h 31 min"),
        (36, "1 min"),
        (10, "1 min"),
    ] as [(TimeInterval, String)])
    func human(seconds: TimeInterval, text: String) {
        #expect(TimeFormatting.human(seconds) == text)
    }

    // MARK: - clock and preview

    @Test func clockUsesTheLocaleAndTimeZone() {
        #expect(TimeFormatting.clock(now, locale: locale, timeZone: timeZone) == "3:42\(narrowSpace)PM")
        #expect(TimeFormatting.clock(now, locale: Locale(identifier: "de_DE"), timeZone: timeZone) == "15:42")
        #expect(TimeFormatting.clock(now, locale: locale, timeZone: .gmt) == "10:42\(narrowSpace)PM")
    }

    @Test func dayShowsTheWeekdayTheDayAndTheMonth() throws {
        #expect(TimeFormatting.day(now, locale: locale, timeZone: timeZone) == "Thu 24 Sep")
        #expect(TimeFormatting.day(now, locale: Locale(identifier: "de_DE"), timeZone: timeZone) == "Do. 24 Sept.")
        // 3:42 PM in Los Angeles is already the next day in Tokyo.
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(TimeFormatting.day(now, locale: locale, timeZone: tokyo) == "Fri 25 Sep")
    }

    @Test func previewShowsTheDurationAndTheEndTime() {
        let text = TimeFormatting.preview(seconds: 5400, now: now, locale: locale, timeZone: timeZone)
        #expect(text == "= 1 h 30 min · ends 5:12\(narrowSpace)PM")
    }

    // MARK: - menuBarName

    @Test func menuBarNameKeepsANameOf24Characters() {
        let name = "Write a cover letter now"
        #expect(name.count == 24)
        #expect(TimeFormatting.menuBarName(name) == name)
    }

    @Test func menuBarNameCutsA25CharacterName() {
        #expect(TimeFormatting.menuBarName("Write a cover letter now!") == "Write a cover letter now…")
    }

    @Test func menuBarNameCountsCharactersNotUTF16Units() {
        let family = "👨‍👩‍👧‍👦"
        let short = String(repeating: family, count: 24)
        let long = String(repeating: family, count: 30)

        #expect(short.utf16.count > 24)
        #expect(TimeFormatting.menuBarName(short) == short)
        #expect(TimeFormatting.menuBarName(long) == short + "…")
    }

    @Test func menuBarNameTrimsWhitespaceBeforeTheEllipsis() {
        let name = "Write the cover letters for Acme"
        #expect(Array(name)[23] == " ")
        #expect(TimeFormatting.menuBarName(name) == "Write the cover letters…")
    }

    // MARK: - compact and taskBadge

    @Test(arguments: [
        (0, "<1m"),
        (59.9, "<1m"),
        (60, "1m"),
        (119, "1m"),
        (2700, "45m"),
        (3120, "52m"),
        (3600, "1h"),
        (5400, "1h 30m"),
        (7259, "2h"),
        // Negative input counts as no time.
        (-30, "<1m"),
    ] as [(TimeInterval, String)])
    func compact(seconds: TimeInterval, text: String) {
        #expect(TimeFormatting.compact(seconds) == text)
    }

    @Test(arguments: [
        // ((estimate, actual), text)
        ((2700, 3120), "45m est · 52m actual"),
        ((2700, 0), "45m est"),
        ((nil, 3120), "52m actual"),
        ((nil, 0), nil),
        // A timer that just started counts as actual time.
        ((1500, 0.5), "25m est · <1m actual"),
    ] as [((TimeInterval?, TimeInterval), String?)])
    func taskBadge(seconds: (estimate: TimeInterval?, actual: TimeInterval), text: String?) {
        #expect(TimeFormatting.taskBadge(estimateSeconds: seconds.estimate, actualSeconds: seconds.actual) == text)
    }
}
