// Last edited: 2026-09-24 20:16 PT

import AppKit
import Testing
@testable import TickTick

@MainActor
struct PopoverKeyHandlerTests {
    // MARK: - Key mapping

    @Test(
        "Each popover key maps to its command",
        arguments: [
            (" ", PopoverKeyCommand.pauseOrResume),
            ("d", .done),
            ("s", .stop),
            ("1", .addOneMinute),
            ("5", .addFiveMinutes),
            ("0", .addTenMinutes),
        ]
    )
    func keyMapsToCommand(key: String, command: PopoverKeyCommand) {
        #expect(PopoverKeyCommand.command(for: key) == command)
    }

    @Test("D and S work in uppercase too (Shift or Caps Lock)")
    func caseInsensitive() {
        #expect(PopoverKeyCommand.command(for: "D") == .done)
        #expect(PopoverKeyCommand.command(for: "S") == .stop)
    }

    @Test("An unmapped key returns nil", arguments: ["x", "2", "", "dd", "\r"])
    func unmappedKeyIsNil(key: String) {
        #expect(PopoverKeyCommand.command(for: key) == nil)
    }

    @Test("1, 5, and 0 add 1, 5, and 10 minutes")
    func extensionAmounts() {
        #expect(PopoverKeyCommand.addOneMinute.extensionSeconds == 60)
        #expect(PopoverKeyCommand.addFiveMinutes.extensionSeconds == 300)
        #expect(PopoverKeyCommand.addTenMinutes.extensionSeconds == 600)
        #expect(PopoverKeyCommand.pauseOrResume.extensionSeconds == nil)
    }

    // MARK: - When a key works

    @Test("A popover key runs when the keys are on, a timer is active, and no field has the keyboard")
    func runsInTheNormalCase() {
        #expect(decision("d") == .run(.done))
        #expect(decision("D", modifiers: .shift) == .run(.done))
    }

    @Test("Popover keys off: every key goes on to the popover, and nothing runs")
    func keysOffPassEverything() {
        for command in PopoverKeyCommand.allCases {
            #expect(decision(command.character, keysEnabled: false) == .pass)
        }
    }

    @Test("With no active timer, the keys do nothing")
    func idlePasses() {
        #expect(decision(" ", timerIsActive: false) == .pass)
    }

    @Test("While the +custom field has the keyboard, Space and the digits are typing")
    func editingTextPasses() {
        #expect(decision(" ", isEditingText: true) == .pass)
        #expect(decision("1", isEditingText: true) == .pass)
    }

    @Test("A key with ⌘, ⌃, or ⌥ is not a popover key (for example ⌘, for Settings)")
    func modifiersPass() {
        #expect(decision("d", modifiers: .command) == .pass)
        #expect(decision("s", modifiers: .control) == .pass)
        #expect(decision("1", modifiers: .option) == .pass)
    }

    @Test("A held key repeats: the repeats do nothing, and do not beep")
    func repeatIsIgnored() {
        #expect(decision(" ", isRepeat: true) == .ignore)
        #expect(decision("x", isRepeat: true) == .pass)
    }

    private func decision(
        _ characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false,
        keysEnabled: Bool = true,
        timerIsActive: Bool = true,
        isEditingText: Bool = false
    ) -> PopoverKeyHandler.Decision {
        PopoverKeyHandler.decision(
            for: .init(characters: characters, modifiers: modifiers, isRepeat: isRepeat),
            in: .init(keysEnabled: keysEnabled, timerIsActive: timerIsActive, isEditingText: isEditingText)
        )
    }
}

@MainActor
struct PopoverKeyPerformTests {
    private let clock = TestClock()
    private let store: ModelStore
    private let service: TaskService
    private let engine: TimerEngine
    private let task: TaskItem
    private let beeps = BeepCounter()

    init() throws {
        store = try ModelStore(inMemory: true)
        let clock = clock
        service = TaskService(context: store.context, now: { clock.now })
        engine = TimerEngine(service: service, clock: clock)
        task = try service.createTask(title: "Write report", in: store.bootstrapInbox())
        engine.start(task: task, seconds: 600)
    }

    @Test("Space pauses a running timer, and Space again resumes it")
    func spacePausesAndResumes() {
        perform(.pauseOrResume)
        #expect(phaseName == "paused")

        perform(.pauseOrResume)
        #expect(phaseName == "running")
    }

    @Test("Space in overtime beeps and changes nothing")
    func spaceInOvertimeBeeps() {
        clock.advance(by: 601)
        engine.checkExpiry()
        let before = engine.state

        perform(.pauseOrResume)

        #expect(engine.state == before)
        #expect(beeps.count == 1)
    }

    @Test("D ends the timer and checks the task")
    func doneChecksTheTask() {
        perform(.done)

        #expect(engine.activeTimer == nil)
        #expect(task.isDone)
    }

    @Test("S ends the timer and keeps the task open")
    func stopKeepsTheTask() {
        perform(.stop)

        #expect(engine.activeTimer == nil)
        #expect(!task.isDone)
    }

    @Test("1, 5, and 0 make the time left grow by 1, 5, and 10 minutes")
    func extendKeysAddTime() {
        perform(.addOneMinute)
        perform(.addFiveMinutes)
        perform(.addTenMinutes)

        // Dates are floating point, so the sum can be a tiny bit off.
        let remaining = engine.activeTimer?.remaining(at: clock.now) ?? 0
        #expect(abs(remaining - (600 + 60 + 300 + 600)) < 0.001)
        #expect(beeps.count == 0)
    }

    private var phaseName: String? {
        switch engine.activeTimer?.phase {
        case .running: "running"
        case .paused: "paused"
        case .overtime: "overtime"
        case nil: nil
        }
    }

    private func perform(_ command: PopoverKeyCommand) {
        PopoverKeyHandler.perform(command, on: engine, beep: beeps.beep)
    }
}

@MainActor
private final class BeepCounter {
    private(set) var count = 0

    func beep() {
        count += 1
    }
}
