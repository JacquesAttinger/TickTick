// Last edited: 2026-09-24 19:58 PT

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TickTick

/// The pure parts of a task row: when the live time redraws, and which clicks open the row's menu.
@MainActor
struct TaskRowTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func timer(_ phase: ActiveTimer.Phase) -> ActiveTimer {
        ActiveTimer(
            taskID: UUID(),
            sessionID: UUID(),
            plannedSeconds: 1500,
            startedAt: now.addingTimeInterval(-60),
            accumulatedActiveSeconds: 0,
            lastResumedAt: now.addingTimeInterval(-60),
            phase: phase
        )
    }

    private func entries(for timer: ActiveTimer, count: Int) -> [TimeInterval] {
        TimerTickSchedule(timer: timer).entries(from: now, mode: .normal).prefix(count).map {
            ($0.timeIntervalSince(now) * 1000).rounded() / 1000
        }
    }

    @Test("A running timer redraws now, then just after each second of the countdown changes, like the label")
    func runningTicksAfterEachSecondChange() {
        // 90.3 s left: the countdown shows 1:31 until 0.3 s from now, then 1:30.
        let running = timer(.running(endDate: now.addingTimeInterval(90.3)))

        #expect(entries(for: running, count: 4) == [0, 0.32, 1.32, 2.32])
    }

    @Test("In overtime, the ticks follow the whole seconds after the end")
    func overtimeTicksAfterEachSecondChange() {
        // 12.75 s over: the count shows +0:12 until 0.25 s from now, then +0:13.
        let overtime = timer(.overtime(since: now.addingTimeInterval(-12.75)))

        #expect(entries(for: overtime, count: 3) == [0, 0.27, 1.27])
    }

    @Test("A paused timer does not change, so it draws one time only")
    func pausedDrawsOnce() {
        let paused = timer(.paused(remaining: 600))

        #expect(entries(for: paused, count: 5) == [0])
    }

    @Test("A right-click and a Control-click open the row menu. A plain click and a key press do not")
    func menuClicks() throws {
        func mouse(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            ))
        }
        let key = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))

        #expect(try TaskRowMenuView.isMenuClick(mouse(.rightMouseDown)))
        #expect(try TaskRowMenuView.isMenuClick(mouse(.leftMouseDown, .control)))
        #expect(try !TaskRowMenuView.isMenuClick(mouse(.leftMouseDown)))
        #expect(try !TaskRowMenuView.isMenuClick(mouse(.rightMouseUp)))
        #expect(!TaskRowMenuView.isMenuClick(key))
    }
}
