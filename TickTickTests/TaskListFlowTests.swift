// Last edited: 2026-09-24 19:20 PT

import Foundation
import Testing
@testable import TickTick

/// The keyboard and timer rules of the Notes window's task list, without a window.
struct TaskListFlowTests {
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    /// A flow with three open tasks and the focus on the draft row.
    private func flowWithThreeTasks() -> TaskListFlow {
        var flow = TaskListFlow()
        _ = flow.handle(.tasksChanged([first, second, third]))
        return flow
    }

    /// A flow with the prompt open on the new task `third`, after a Return on the draft.
    private func flowWithPromptOnNewTask() -> TaskListFlow {
        var flow = TaskListFlow()
        _ = flow.handle(.tasksChanged([first, second]))
        _ = flow.handle(.submitDraft(title: "Research"))
        _ = flow.handle(.taskCreated(id: third))
        return flow
    }

    /// A flow on the switch question for a 25 min timer on `third`.
    private func flowOnSwitchQuestion() -> TaskListFlow {
        var flow = flowWithPromptOnNewTask()
        _ = flow.handle(.startRequested(seconds: 1500))
        _ = flow.handle(.engineNeedsConfirmation)
        return flow
    }

    // MARK: - Draft row

    @Test("A new flow has no rows, the focus on the draft row, and nothing open")
    func newFlow() {
        let flow = TaskListFlow()

        #expect(flow.rows.isEmpty)
        #expect(flow.focus == .draft)
        #expect(flow.inline == nil)
    }

    @Test("Whitespace-only Return on the draft row does nothing", arguments: ["", "   ", "\n\t"])
    func whitespaceDraftReturnDoesNothing(text: String) {
        var flow = flowWithThreeTasks()
        let before = flow

        #expect(flow.handle(.submitDraft(title: text)).isEmpty)
        #expect(flow == before)
    }

    @Test("Return on the draft row creates the trimmed task at the end and opens the prompt on it")
    func draftReturnCreatesTheTaskAndOpensThePrompt() {
        var flow = flowWithThreeTasks()
        let created = UUID()

        #expect(flow.handle(.submitDraft(title: "  Write intro \n")) == [.createTask(title: "Write intro")])
        #expect(flow.handle(.taskCreated(id: created)).isEmpty)

        #expect(flow.rows == [first, second, third, created])
        #expect(flow.inline == .prompt(taskID: created))
        #expect(flow.focus == .task(created))
    }

    @Test("Focus loss on a typed draft saves the task with no prompt")
    func draftFocusLossSavesWithoutPrompt() {
        var flow = flowWithThreeTasks()
        let created = UUID()

        #expect(flow.handle(.draftFocusLost(title: " Outline ")) == [.createTask(title: "Outline")])
        _ = flow.handle(.taskCreated(id: created))

        #expect(flow.rows.last == created)
        #expect(flow.inline == nil)
    }

    @Test("Focus loss on an empty draft saves nothing")
    func emptyDraftFocusLossSavesNothing() {
        var flow = flowWithThreeTasks()

        #expect(flow.handle(.draftFocusLost(title: "  ")).isEmpty)
    }

    // MARK: - Prompt

    @Test("Return in the prompt starts the timer on the task with replacing false")
    func promptReturnStartsWithoutReplacing() {
        var flow = flowWithPromptOnNewTask()

        let effects = flow.handle(.startRequested(seconds: 1500))

        #expect(effects == [.startTimer(taskID: third, seconds: 1500, replacing: false)])
        #expect(flow.inline == .prompt(taskID: third))
    }

    @Test("When the timer starts, the prompt closes and the focus goes to the draft row")
    func timerStartedClosesThePrompt() {
        var flow = flowWithPromptOnNewTask()
        _ = flow.handle(.startRequested(seconds: 1500))

        #expect(flow.handle(.timerStarted).isEmpty)
        #expect(flow.inline == nil)
        #expect(flow.focus == .draft)
    }

    @Test("Esc in the prompt keeps the task, starts nothing, and focuses the draft row")
    func escapeKeepsTheTaskAndStartsNothing() {
        var flow = flowWithPromptOnNewTask()

        #expect(flow.handle(.skipDuration).isEmpty)
        #expect(flow.rows == [first, second, third])
        #expect(flow.inline == nil)
        #expect(flow.focus == .draft)
    }

    @Test("▶ opens the prompt on its row and closes a prompt on another row")
    func playOpensThePromptOnItsRow() {
        var flow = flowWithPromptOnNewTask()

        #expect(flow.handle(.playTapped(id: first)).isEmpty)
        #expect(flow.inline == .prompt(taskID: first))
        #expect(flow.focus == .task(first))
        #expect(flow.handle(.startRequested(seconds: 300)) == [
            .startTimer(taskID: first, seconds: 300, replacing: false),
        ])
    }

    @Test("▶ on a task that is not in the list does nothing")
    func playOnAnUnknownTaskDoesNothing() {
        var flow = flowWithThreeTasks()

        _ = flow.handle(.playTapped(id: UUID()))

        #expect(flow.inline == nil)
        #expect(flow.focus == .draft)
    }

    // MARK: - Switch question

    @Test("When another timer is active, the prompt turns into the switch question")
    func engineNeedsConfirmationShowsTheQuestion() {
        let flow = flowOnSwitchQuestion()

        #expect(flow.inline == .confirmSwitch(taskID: third, pendingSeconds: 1500))
    }

    @Test("Stop & Start on the question starts the timer with replacing true, then closes")
    func confirmStartsWithReplacing() {
        var flow = flowOnSwitchQuestion()

        #expect(flow.handle(.confirmSwitch) == [.startTimer(taskID: third, seconds: 1500, replacing: true)])
        _ = flow.handle(.timerStarted)
        #expect(flow.inline == nil)
        #expect(flow.focus == .draft)
    }

    @Test("Cancel on the question goes back to the prompt on the same task, with no start")
    func cancelReturnsToThePrompt() {
        var flow = flowOnSwitchQuestion()

        #expect(flow.handle(.cancelSwitch).isEmpty)
        #expect(flow.inline == .prompt(taskID: third))
        #expect(flow.handle(.confirmSwitch).isEmpty)
        #expect(flow.handle(.startRequested(seconds: 600)) == [
            .startTimer(taskID: third, seconds: 600, replacing: false),
        ])
    }

    @Test("Prompt events without an open prompt do nothing")
    func promptEventsWithoutAPromptDoNothing() {
        var flow = flowWithThreeTasks()
        let before = flow

        for event: TaskListFlow.Event in [
            .startRequested(seconds: 60), .skipDuration, .timerStarted, .engineNeedsConfirmation,
            .confirmSwitch, .cancelSwitch,
        ] {
            #expect(flow.handle(event).isEmpty)
        }
        #expect(flow == before)
    }
}

/// Return, ⌫, the arrows, and the focus rules on task rows.
extension TaskListFlowTests {
    // MARK: - Rows

    @Test("Return on a task row saves the new title and moves the focus down")
    func rowReturnRenamesAndMovesDown() {
        var flow = flowWithThreeTasks()
        _ = flow.handle(.focusChanged(.task(first)))

        #expect(flow.handle(.submitRow(id: first, title: " Outline v2 ")) == [
            .renameTask(id: first, title: "Outline v2"),
        ])
        #expect(flow.focus == .task(second))
        #expect(flow.inline == nil)
    }

    @Test("Return on the last task row moves the focus to the draft row")
    func lastRowReturnMovesToTheDraft() {
        var flow = flowWithThreeTasks()
        _ = flow.handle(.focusChanged(.task(third)))

        _ = flow.handle(.submitRow(id: third, title: "Research"))

        #expect(flow.focus == .draft)
    }

    @Test("An emptied title saves nothing, on Return and on focus loss")
    func emptiedTitleSavesNothing() {
        var flow = flowWithThreeTasks()
        _ = flow.handle(.focusChanged(.task(first)))

        #expect(flow.handle(.rowFocusLost(id: first, title: "  ")).isEmpty)
        #expect(flow.handle(.submitRow(id: first, title: "")).isEmpty)
        #expect(flow.focus == .task(second))
    }

    @Test("Focus loss on a task row saves its title")
    func rowFocusLossRenames() {
        var flow = flowWithThreeTasks()

        #expect(flow.handle(.rowFocusLost(id: second, title: "Outline")) == [.renameTask(id: second, title: "Outline")])
    }

    @Test("⌫ on an empty task row deletes it and focuses the row above")
    func deleteBackwardOnEmptyRowDeletesIt() {
        var flow = flowWithThreeTasks()
        _ = flow.handle(.focusChanged(.task(second)))

        #expect(flow.handle(.deleteBackwardOnEmpty(id: second)) == [.deleteTask(id: second)])
        #expect(flow.rows == [first, third])
        #expect(flow.focus == .task(first))
    }

    @Test("⌫ on the empty first row deletes it and focuses the row that is now first")
    func deleteBackwardOnFirstRow() {
        var flow = flowWithThreeTasks()
        _ = flow.handle(.focusChanged(.task(first)))

        #expect(flow.handle(.deleteBackwardOnEmpty(id: first)) == [.deleteTask(id: first)])
        #expect(flow.focus == .task(second))
    }

    @Test("⌫ on the empty only row deletes it and focuses the draft row")
    func deleteBackwardOnOnlyRow() {
        var flow = TaskListFlow()
        _ = flow.handle(.tasksChanged([first]))

        #expect(flow.handle(.deleteBackwardOnEmpty(id: first)) == [.deleteTask(id: first)])
        #expect(flow.focus == .draft)
    }

    @Test("⌫ on the empty draft row only moves the focus up, and the draft row stays")
    func deleteBackwardOnDraftOnlyMovesUp() {
        var flow = flowWithThreeTasks()

        #expect(flow.handle(.deleteBackwardOnEmptyDraft).isEmpty)
        #expect(flow.focus == .task(third))
        #expect(flow.rows == [first, second, third])
    }

    @Test("⌫ on the draft row of an empty note does nothing")
    func deleteBackwardOnDraftOfEmptyNote() {
        var flow = TaskListFlow()

        #expect(flow.handle(.deleteBackwardOnEmptyDraft).isEmpty)
        #expect(flow.focus == .draft)
    }

    // MARK: - Arrows

    @Test("↑ and ↓ move one row, with the draft row as the last stop")
    func arrowsMoveOneRow() {
        var flow = flowWithThreeTasks()

        _ = flow.handle(.moveUp)
        #expect(flow.focus == .task(third))
        _ = flow.handle(.moveUp)
        #expect(flow.focus == .task(second))
        _ = flow.handle(.moveDown)
        #expect(flow.focus == .task(third))
        _ = flow.handle(.moveDown)
        #expect(flow.focus == .draft)
    }

    @Test("Arrows clamp at both ends")
    func arrowsClampAtBothEnds() {
        var flow = flowWithThreeTasks()

        _ = flow.handle(.moveDown)
        #expect(flow.focus == .draft)
        for _ in 0 ..< 5 {
            _ = flow.handle(.moveUp)
        }
        #expect(flow.focus == .task(first))
    }

    @Test("Arrows in an empty note stay on the draft row")
    func arrowsInAnEmptyNote() {
        var flow = TaskListFlow()

        _ = flow.handle(.moveUp)
        _ = flow.handle(.moveDown)

        #expect(flow.focus == .draft)
    }

    // MARK: - Focus and outside changes

    @Test("A click in another row closes the prompt, and the task stays without a timer")
    func clickElsewhereClosesThePrompt() {
        var flow = flowWithPromptOnNewTask()

        #expect(flow.handle(.focusChanged(.task(first))).isEmpty)
        #expect(flow.inline == nil)
        #expect(flow.focus == .task(first))
    }

    @Test("A click in the row of the open question closes it")
    func clickInTheQuestionRowClosesIt() {
        var flow = flowOnSwitchQuestion()

        _ = flow.handle(.focusChanged(.task(third)))

        #expect(flow.inline == nil)
        #expect(flow.focus == .task(third))
    }

    @Test("When the prompt's task leaves the list (checked or deleted), the prompt closes")
    func promptClosesWhenItsTaskLeaves() {
        var flow = flowWithPromptOnNewTask()

        _ = flow.handle(.tasksChanged([first, second]))

        #expect(flow.inline == nil)
        #expect(flow.focus == .draft)
    }

    @Test("When the focused task leaves the list, the row now in its place gets the focus")
    func focusMovesWhenTheFocusedTaskLeaves() {
        var flow = flowWithThreeTasks()
        _ = flow.handle(.focusChanged(.task(second)))

        _ = flow.handle(.tasksChanged([first, third]))

        #expect(flow.focus == .task(third))
    }

    @Test("A focus report for a row that does not exist does nothing")
    func focusOnAMissingRowDoesNothing() {
        var flow = flowWithThreeTasks()

        _ = flow.handle(.focusChanged(.task(UUID())))

        #expect(flow.focus == .draft)
    }

    @Test("Focus is never nil: after any event sequence it names an existing row")
    func focusAlwaysNamesAnExistingRow() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0 ..< 200 {
            var harness = FlowHarness()
            for _ in 0 ..< 40 {
                harness.send(harness.randomEvent(using: &generator))
                #expect(harness.focusIsValid, "Focus \(harness.flow.focus) is not a row in \(harness.flow.rows)")
            }
        }
    }
}

/// Runs a flow like `TaskListModel` does: it saves created tasks, deletes deleted ones, and sends the results back.
private struct FlowHarness {
    private(set) var flow = TaskListFlow()
    private var tasks: [UUID] = []
    private var timerIsActive = false

    var focusIsValid: Bool {
        let focusExists = switch flow.focus {
        case .draft: true
        case let .task(id): flow.rows.contains(id)
        }
        let inlineExists = flow.inline.map { flow.rows.contains($0.taskID) } ?? true
        return focusExists && inlineExists
    }

    mutating func send(_ event: TaskListFlow.Event) {
        for effect in flow.handle(event) {
            switch effect {
            case .createTask:
                let id = UUID()
                tasks.append(id)
                send(.taskCreated(id: id))
            case let .deleteTask(id):
                tasks.removeAll { $0 == id }
                send(.tasksChanged(tasks))
            case .renameTask:
                break
            case let .startTimer(_, _, replacing):
                if timerIsActive, !replacing {
                    send(.engineNeedsConfirmation)
                } else {
                    timerIsActive = true
                    send(.timerStarted)
                }
            }
        }
    }

    /// A random user action, or a random change from outside the window (a task checked in the popover).
    mutating func randomEvent(using generator: inout SeededGenerator) -> TaskListFlow.Event {
        let someTask = tasks.randomElement(using: &generator) ?? UUID()
        let events: [TaskListFlow.Event] = [
            .submitDraft(title: "Task"), .submitDraft(title: " "), .draftFocusLost(title: "Task"),
            .submitRow(id: someTask, title: "Renamed"), .rowFocusLost(id: someTask, title: ""),
            .playTapped(id: someTask), .startRequested(seconds: 60), .skipDuration, .confirmSwitch, .cancelSwitch,
            .deleteBackwardOnEmpty(id: someTask), .deleteBackwardOnEmptyDraft, .moveUp, .moveDown,
            .focusChanged(.task(someTask)), .focusChanged(.draft),
        ]
        if Int.random(in: 0 ..< 10, using: &generator) == 0, !tasks.isEmpty {
            tasks.remove(at: Int.random(in: 0 ..< tasks.count, using: &generator))
            return .tasksChanged(tasks)
        }
        return events.randomElement(using: &generator) ?? .moveUp
    }
}

/// A small repeatable random number generator (SplitMix64), so a failing sequence can be run again.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
