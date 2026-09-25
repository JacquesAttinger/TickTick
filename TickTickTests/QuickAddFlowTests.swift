// Last edited: 2026-09-24 17:58 PT

import Foundation
import Testing
@testable import TickTick

struct QuickAddFlowTests {
    /// A flow on step 2, after the task "Write cover letter" was saved.
    private func flowOnDuration() -> QuickAddFlow {
        var flow = QuickAddFlow()
        _ = flow.handle(.submitTask("Write cover letter"))
        return flow
    }

    /// A flow on the switch question for a 25 min timer.
    private func flowOnConfirmation() -> QuickAddFlow {
        var flow = flowOnDuration()
        _ = flow.handle(.startRequested(seconds: 1500))
        _ = flow.handle(.engineNeedsConfirmation)
        return flow
    }

    // MARK: - Step 1

    @Test("A new flow starts on step 1")
    func startsOnTheTaskStep() {
        #expect(QuickAddFlow().step == .task)
    }

    @Test("Return on step 1 saves the trimmed title and goes to step 2")
    func submitTaskSavesTheTask() {
        var flow = QuickAddFlow()

        let effects = flow.handle(.submitTask("  Write cover letter \n"))

        #expect(effects == [.createTask(title: "Write cover letter")])
        #expect(flow.step == .duration)
        #expect(flow.taskTitle == "Write cover letter")
    }

    @Test("A whitespace-only title does nothing", arguments: ["", "   ", "\n\t"])
    func whitespaceOnlyTitleDoesNothing(text: String) {
        var flow = QuickAddFlow()

        #expect(flow.handle(.submitTask(text)).isEmpty)
        #expect(flow.step == .task)
        #expect(flow.taskTitle == nil)
    }

    @Test("Esc on step 1 closes without a task")
    func escapeOnStepOneClosesWithoutATask() {
        var flow = QuickAddFlow()

        #expect(flow.handle(.escapeOnTask) == [.close])
        #expect(flow.step == .closed)
    }

    // MARK: - Step 2

    @Test("Return on a valid duration starts the timer without replacing, and the start closes the panel")
    func startRequestedStartsTheTimer() {
        var flow = flowOnDuration()

        #expect(flow.handle(.startRequested(seconds: 1500)) == [.startTimer(seconds: 1500, replacing: false)])
        #expect(flow.step == .duration)
        #expect(flow.handle(.timerStarted) == [.close])
        #expect(flow.step == .closed)
    }

    @Test("A chip starts at once: it is the same start request as Return")
    func chipStartsAtOnce() {
        var flow = flowOnDuration()

        #expect(flow.handle(.startRequested(seconds: 300)) == [.startTimer(seconds: 300, replacing: false)])
    }

    @Test("Esc on step 2 keeps the task and starts nothing")
    func escapeOnStepTwoKeepsTheTask() {
        var flow = flowOnDuration()

        let effects = flow.handle(.skipDuration)

        #expect(effects == [.close])
        #expect(!effects.contains {
            if case .startTimer = $0 {
                true
            } else {
                false
            }
        })
        #expect(flow.step == .closed)
    }

    @Test("Step 1 events do nothing on step 2, and step 2 events do nothing on step 1")
    func eventsOfOtherStepsDoNothing() {
        var onDuration = flowOnDuration()
        #expect(onDuration.handle(.submitTask("Again")).isEmpty)
        #expect(onDuration.handle(.escapeOnTask).isEmpty)
        #expect(onDuration.step == .duration)

        var onTask = QuickAddFlow()
        #expect(onTask.handle(.startRequested(seconds: 60)).isEmpty)
        #expect(onTask.handle(.skipDuration).isEmpty)
        #expect(onTask.step == .task)
    }

    // MARK: - Switch confirmation

    @Test("An active timer turns the start into the switch question")
    func engineNeedsConfirmationAsks() {
        #expect(flowOnConfirmation().step == .confirmSwitch(pendingSeconds: 1500))
    }

    @Test("Confirm starts the pending duration with replacing: true, and the start closes the panel")
    func confirmSwitchReplaces() {
        var flow = flowOnConfirmation()

        #expect(flow.handle(.confirmSwitch) == [.startTimer(seconds: 1500, replacing: true)])
        #expect(flow.handle(.timerStarted) == [.close])
        #expect(flow.step == .closed)
    }

    @Test("Cancel returns to step 2 and starts nothing")
    func cancelSwitchReturnsToTheDurationStep() {
        var flow = flowOnConfirmation()

        #expect(flow.handle(.cancelSwitch).isEmpty)
        #expect(flow.step == .duration)
        #expect(flow.taskTitle == "Write cover letter")
    }

    @Test("A new start after Cancel asks again with the new duration")
    func startAfterCancelAsksAgain() {
        var flow = flowOnConfirmation()
        _ = flow.handle(.cancelSwitch)

        #expect(flow.handle(.startRequested(seconds: 600)) == [.startTimer(seconds: 600, replacing: false)])
        _ = flow.handle(.engineNeedsConfirmation)
        #expect(flow.step == .confirmSwitch(pendingSeconds: 600))
    }

    // MARK: - Focus loss

    @Test("Focus loss on step 1 closes without a task")
    func focusLostOnStepOne() {
        var flow = QuickAddFlow()

        #expect(flow.handle(.focusLost) == [.close])
        #expect(flow.step == .closed)
    }

    @Test("Focus loss on step 2 closes, keeps the task, and starts nothing")
    func focusLostOnStepTwo() {
        var flow = flowOnDuration()

        #expect(flow.handle(.focusLost) == [.close])
        #expect(flow.step == .closed)
    }

    @Test("Focus loss on the switch question closes and keeps the old timer")
    func focusLostOnConfirmation() {
        var flow = flowOnConfirmation()

        #expect(flow.handle(.focusLost) == [.close])
        #expect(flow.step == .closed)
    }

    @Test("After the close, every event does nothing, so a late focus loss cannot close twice")
    func closedIgnoresEverything() {
        var flow = QuickAddFlow()
        _ = flow.handle(.escapeOnTask)
        let events: [QuickAddFlow.Event] = [
            .submitTask("A"), .startRequested(seconds: 60), .skipDuration, .escapeOnTask, .timerStarted,
            .engineNeedsConfirmation, .confirmSwitch, .cancelSwitch, .focusLost,
        ]

        for event in events {
            #expect(flow.handle(event).isEmpty)
        }
        #expect(flow.step == .closed)
    }
}
