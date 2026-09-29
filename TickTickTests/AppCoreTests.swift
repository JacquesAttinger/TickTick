// Last edited: 2026-09-29 18:35 CDT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// App launch: the saved timer comes back, and `-debugStartTimerSeconds N` starts a debug timer.
/// Each "launch" builds a new `AppCore` on the same data and the same saved-timer key.
@MainActor
struct AppCoreTests {
    private let clock = TestClock()
    private let modelStore: ModelStore
    private let saved: TestTimerDefaults

    init() throws {
        modelStore = try ModelStore(inMemory: true)
        saved = try TestTimerDefaults()
    }

    @Test("The test host does not open the real store or restore the saved timer")
    func hostSkipsTheCore() {
        #expect(AppDelegate.isRunningUnitTests)
    }

    // MARK: - Debug launch argument

    @Test(
        "seconds(in:) reads a number of seconds above 0 and not over 24 h",
        arguments: [
            ("60", 60),
            (" 90 ", 90),
            ("0.5", 0.5),
            ("86400", 86400),
        ] as [(String, TimeInterval)]
    )
    func debugSecondsAcceptsValidValues(text: String, seconds: TimeInterval) {
        #expect(DebugTimerLaunch.seconds(in: [DebugTimerLaunch.argument: text]) == seconds)
    }

    @Test("seconds(in:) rejects a missing, empty, zero, negative, too long, or non-number value",
          arguments: ["", "0", "-5", "86401", "abc", "1m", "nan", "inf"])
    func debugSecondsRejectsInvalidValues(text: String) {
        #expect(DebugTimerLaunch.seconds(in: [DebugTimerLaunch.argument: text]) == nil)
        #expect(DebugTimerLaunch.seconds(in: [:]) == nil)
    }

    @Test("seconds(in:) also reads a number value")
    func debugSecondsReadsNumbers() {
        #expect(DebugTimerLaunch.seconds(in: [DebugTimerLaunch.argument: NSNumber(value: 45)]) == 45)
    }

    @Test("-debugStartTimerSeconds starts a timer on a new Inbox task named Debug timer")
    func debugArgumentStartsATimer() throws {
        let core = launch(arguments: ["debugStartTimerSeconds": "60"])

        let timer = try #require(core.timerEngine.activeTimer)
        #expect(timer.phase == .running(endDate: clock.now.addingTimeInterval(60)))
        let task = try #require(core.timerEngine.activeTask)
        #expect(task.title == "Debug timer")
        #expect(task.note?.isInbox == true)
        #expect(task.estimateSeconds == 60)
        #expect(saved.savedText != nil)
    }

    @Test("A second debug launch reuses the task and replaces the old timer")
    func debugRelaunchReusesTheTask() throws {
        let first = launch(arguments: ["debugStartTimerSeconds": "60"])
        let oldSessionID = try #require(first.timerEngine.activeTimer?.sessionID)
        clock.advance(by: 10)

        let second = launch(arguments: ["debugStartTimerSeconds": "120"])

        let debugTasks = try modelStore.context.fetch(FetchDescriptor<TaskItem>()).filter { $0.title == "Debug timer" }
        #expect(debugTasks.count == 1)
        #expect(second.taskService.session(withID: oldSessionID)?.outcome == .replaced)
        #expect(second.timerEngine.activeTimer?.phase == .running(endDate: clock.now.addingTimeInterval(120)))
        #expect(debugTasks.first?.estimateSeconds == 120)
    }

    @Test("An invalid debug value starts nothing")
    func invalidDebugValueStartsNothing() {
        let core = launch(arguments: ["debugStartTimerSeconds": "soon"])

        #expect(core.timerEngine.state == .idle)
    }

    // MARK: - Restore on relaunch

    @Test("A plain relaunch restores the saved timer")
    func plainRelaunchRestoresTheTimer() throws {
        let first = launch(arguments: ["debugStartTimerSeconds": "60"])
        let before = first.timerEngine.state
        clock.advance(by: 10)

        let second = launch(arguments: [:])

        #expect(second.timerEngine.state == before)
        #expect(try #require(second.timerEngine.activeTimer).remaining(at: clock.now) == 50)
    }

    // MARK: - Quick-add note

    @Test("quickAddNote is the Inbox when no note is saved")
    func quickAddNoteDefaultsToInbox() throws {
        let core = launch(arguments: [:])

        #expect(try core.quickAddNote().isInbox)
    }

    @Test("quickAddNote is the saved selected note")
    func quickAddNoteIsTheSelectedNote() throws {
        let core = launch(arguments: [:])
        let work = core.taskService.createNote(title: "Work")
        core.selectedNoteStore.noteID = work.id

        #expect(try core.quickAddNote() === work)
    }

    @Test("quickAddNote is the Inbox when the saved note was deleted")
    func quickAddNoteFallsBackWhenTheNoteIsDeleted() throws {
        let core = launch(arguments: [:])
        let work = core.taskService.createNote(title: "Work")
        core.selectedNoteStore.noteID = work.id
        try core.taskService.deleteNote(work)

        #expect(try core.quickAddNote().isInbox)
    }

    // MARK: - Helpers

    private func launch(arguments: [String: Any]) -> AppCore {
        let core = AppCore(
            modelStore: modelStore,
            activeTimerStore: saved.makeStore(),
            selectedNoteStore: saved.makeSelectedNoteStore(),
            clock: clock,
            schedulesExpiry: false
        )
        core.startTimer(launchArguments: arguments)
        return core
    }
}
