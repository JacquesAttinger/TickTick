// Last edited: 2026-09-24 17:58 PT

import Foundation

/// The rules of the quick-add panel, as a pure state machine. `QuickAddSession` feeds it events and runs the
/// effects it returns, so tests can check every Return, Esc, chip, and focus rule without a window.
///
/// Step 1 (`task`): Return saves the task in the Inbox at once and goes to step 2. Esc closes with nothing saved.
/// Step 2 (`duration`): Return or a chip starts the timer. Esc closes, and the task stays without a timer.
/// When another timer is active, step 2 asks first (`confirmSwitch`, product decision 8).
/// Focus loss (a click elsewhere, or the hotkey again) closes the panel with the Esc rule of the current step.
struct QuickAddFlow: Equatable {
    enum Step: Equatable {
        case task
        case duration
        /// Another timer is active. `pendingSeconds` is the new timer's duration.
        case confirmSwitch(pendingSeconds: TimeInterval)
        /// The panel closed. Every later event does nothing.
        case closed
    }

    enum Event: Equatable {
        /// Return on step 1 with the typed title.
        case submitTask(String)
        /// Return on a valid duration, or a chip click.
        case startRequested(seconds: TimeInterval)
        /// Esc on step 2.
        case skipDuration
        /// Esc on step 1.
        case escapeOnTask
        /// The engine started the timer.
        case timerStarted
        /// The engine did not start the timer, because another timer is active.
        case engineNeedsConfirmation
        /// "Stop & Start" (or Return) on the switch question.
        case confirmSwitch
        /// "Cancel" (or Esc) on the switch question.
        case cancelSwitch
        /// The panel lost key status, or the hotkey closed it.
        case focusLost
    }

    enum Effect: Equatable {
        /// Add an open task with this title at the end of the Inbox.
        case createTask(title: String)
        /// Start a timer on the new task. Send `timerStarted` or `engineNeedsConfirmation` back with the result.
        case startTimer(seconds: TimeInterval, replacing: Bool)
        case close
    }

    private(set) var step: Step = .task
    /// The saved task's title, from step 2 on.
    private(set) var taskTitle: String?
    /// The duration of the start that waits for the engine's answer.
    private var pendingSeconds: TimeInterval?

    /// Moves to the next step and returns what the caller must do, in order.
    mutating func handle(_ event: Event) -> [Effect] {
        switch (step, event) {
        case let (.task, .submitTask(text)):
            let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                return []
            }
            taskTitle = title
            step = .duration
            return [.createTask(title: title)]
        case let (.duration, .startRequested(seconds)):
            pendingSeconds = seconds
            return [.startTimer(seconds: seconds, replacing: false)]
        case (.duration, .engineNeedsConfirmation):
            guard let pendingSeconds else {
                return []
            }
            step = .confirmSwitch(pendingSeconds: pendingSeconds)
            return []
        case let (.confirmSwitch(seconds), .confirmSwitch):
            return [.startTimer(seconds: seconds, replacing: true)]
        case (.confirmSwitch, .cancelSwitch):
            pendingSeconds = nil
            step = .duration
            return []
        case (.task, .escapeOnTask), (.duration, .skipDuration),
             (.duration, .timerStarted), (.confirmSwitch, .timerStarted),
             (.task, .focusLost), (.duration, .focusLost), (.confirmSwitch, .focusLost):
            return close()
        default:
            return []
        }
    }

    private mutating func close() -> [Effect] {
        step = .closed
        return [.close]
    }
}
