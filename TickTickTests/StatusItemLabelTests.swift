// Last edited: 2026-09-24 15:33 PT

import AppKit
import Foundation
import Testing
@testable import TickTick

struct StatusItemLabelTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let name = "Write cover letter"

    // MARK: - Text and color per state

    @Test("Idle shows only the timer symbol")
    func idle() throws {
        let label = StatusItemLabel.make(for: nil, taskName: name, now: now)

        #expect(label.string == "⏱")
        #expect(try color(of: label) == .labelColor)
    }

    @Test("Running shows the name and the time left in the label color")
    func running() throws {
        let label = StatusItemLabel.make(for: timer(.running(endDate: now + 1453)), taskName: name, now: now)

        #expect(label.string == "⏱ Write cover letter · 24:13")
        #expect(try color(of: label) == .labelColor)
    }

    @Test("Paused shows the pause symbol and the frozen time, dimmed")
    func paused() throws {
        let label = StatusItemLabel.make(for: timer(.paused(remaining: 1453)), taskName: name, now: now)

        #expect(label.string == "⏸ Write cover letter · 24:13")
        #expect(try color(of: label) == .secondaryLabelColor)
    }

    @Test("Overtime counts up in red")
    func overtime() throws {
        let label = StatusItemLabel.make(for: timer(.overtime(since: now - 133)), taskName: name, now: now)

        #expect(label.string == "⏱ Write cover letter · +2:13")
        #expect(try color(of: label) == .systemRed)
    }

    @Test("A name over 24 characters is cut and gets …")
    func longNameIsCut() {
        let text = StatusItemLabel.text(
            for: timer(.running(endDate: now + 60)),
            taskName: "Prepare the quarterly board deck",
            now: now
        )

        #expect(text == "⏱ Prepare the quarterly bo… · 1:00")
    }

    @Test("A name of exactly 24 characters is not cut")
    func nameAtTheLimitIsKept() {
        let text = StatusItemLabel.text(
            for: timer(.running(endDate: now + 60)),
            taskName: "Twenty-four characters!!",
            now: now
        )

        #expect(text == "⏱ Twenty-four characters!! · 1:00")
    }

    @Test("An empty or blank name shows only the symbol and the time")
    func blankName() {
        let text = StatusItemLabel.text(for: timer(.running(endDate: now + 60)), taskName: "  ", now: now)

        #expect(text == "⏱ 1:00")
    }

    // MARK: - Font

    @Test("The label uses the menu bar font size with digits of one width")
    func fontHasMonospacedDigits() throws {
        let label = StatusItemLabel.make(for: timer(.running(endDate: now + 60)), taskName: name, now: now)
        let font = try #require(label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(font.pointSize == NSFont.menuBarFont(ofSize: 0).pointSize)
        let widths = Set((0 ... 9).map { NSAttributedString(string: "\($0)", attributes: [.font: font]).size().width })
        #expect(widths.count == 1)
    }

    // MARK: - Refresh timing

    @Test("While running, the next change is when the time left passes a whole second")
    func nextChangeWhileRunning() throws {
        let partial = try #require(StatusItemLabel.nextChange(for: timer(.running(endDate: now + 59.75)), after: now))
        let whole = try #require(StatusItemLabel.nextChange(for: timer(.running(endDate: now + 60)), after: now))

        #expect(abs(partial.timeIntervalSince(now) - 0.75) < 0.000_1)
        #expect(whole == now + 1)
    }

    @Test("In overtime, the next change is when the overtime passes a whole second")
    func nextChangeInOvertime() throws {
        let next = try #require(StatusItemLabel.nextChange(for: timer(.overtime(since: now - 2.25)), after: now))

        #expect(abs(next.timeIntervalSince(now) - 0.75) < 0.000_1)
    }

    @Test("Idle and paused labels do not change by themselves")
    func nextChangeWhenFrozen() {
        #expect(StatusItemLabel.nextChange(for: nil, after: now) == nil)
        #expect(StatusItemLabel.nextChange(for: timer(.paused(remaining: 30)), after: now) == nil)
    }

    // MARK: - Helpers

    private func timer(_ phase: ActiveTimer.Phase) -> ActiveTimer {
        ActiveTimer(
            taskID: UUID(),
            sessionID: UUID(),
            plannedSeconds: 1500,
            startedAt: now - 60,
            accumulatedActiveSeconds: 0,
            lastResumedAt: now,
            phase: phase
        )
    }

    private func color(of label: NSAttributedString) throws -> NSColor {
        try #require(label.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
    }
}
