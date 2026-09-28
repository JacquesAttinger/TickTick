// Last edited: 2026-09-28 17:40 PT

import Foundation
@testable import TickTick

/// Runs a flow like `TaskListModel` does: it saves created tasks, deletes deleted ones, and sends the results back.
struct FlowHarness {
    private(set) var flow = TaskListFlow()
    private var tasks: [UUID] = []
    private var done: Set<UUID> = []
    private var timerIsActive = false

    /// The focus names an existing row, and the prompt or the question shows only under an open task.
    var focusIsValid: Bool {
        let focusExists = switch flow.focus {
        case .draft: true
        case let .task(id): flow.rows.contains(id)
        }
        let inlineIsValid = flow.inline.map { flow.rows.contains($0.taskID) && !done.contains($0.taskID) } ?? true
        return focusExists && inlineIsValid
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
                done.remove(id)
                send(.tasksChanged(tasks, done: done))
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

    /// A random user action, or a random change to the tasks: a delete, a check or an uncheck (also Done in the
    /// popover), or a drag to a new place.
    mutating func randomEvent(using generator: inout SeededGenerator) -> TaskListFlow.Event {
        let someTask = tasks.randomElement(using: &generator) ?? UUID()
        let events: [TaskListFlow.Event] = [
            .submitDraft(title: "Task"), .submitDraft(title: " "), .draftFocusLost(title: "Task"),
            .submitRow(id: someTask, title: "Renamed"), .rowFocusLost(id: someTask, title: ""),
            .playTapped(id: someTask), .startRequested(seconds: 60), .skipDuration, .confirmSwitch, .cancelSwitch,
            .deleteBackwardOnEmpty(id: someTask), .deleteBackwardOnEmptyDraft, .moveUp, .moveDown,
            .focusChanged(.task(someTask)), .focusChanged(.draft),
        ]
        if Int.random(in: 0 ..< 5, using: &generator) == 0, !tasks.isEmpty {
            return randomTaskChange(using: &generator)
        }
        return events.randomElement(using: &generator) ?? .moveUp
    }

    private mutating func randomTaskChange(using generator: inout SeededGenerator) -> TaskListFlow.Event {
        let index = Int.random(in: 0 ..< tasks.count, using: &generator)
        switch Int.random(in: 0 ..< 3, using: &generator) {
        case 0:
            done.remove(tasks.remove(at: index))
        case 1:
            if done.remove(tasks[index]) == nil {
                done.insert(tasks[index])
            }
        default:
            let moved = tasks.remove(at: index)
            tasks.insert(moved, at: Int.random(in: 0 ... tasks.count, using: &generator))
        }
        return .tasksChanged(tasks, done: done)
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
