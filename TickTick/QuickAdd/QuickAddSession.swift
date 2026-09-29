// Last edited: 2026-09-29 18:25 CDT

import Foundation
import Observation
import os

/// One opening of the quick-add panel: the flow, the typed text, and the task it saved.
///
/// `QuickAddView` shows it and sends it events. It runs the flow's effects on the real data: it adds the task to
/// the target note (the selected note, or the Inbox) through `TaskService` and starts the timer through
/// `TimerEngine`. The panel builds a new session on every opening, so no half-typed text comes back.
@Observable
@MainActor
final class QuickAddSession {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "QuickAdd")

    private(set) var flow = QuickAddFlow()
    var taskText = ""
    /// Owned here, not by the duration field, so a cancelled switch question gives the typed duration back.
    var durationText = ""
    /// The task that step 1 saved.
    private(set) var task: TaskItem?
    /// The title of the note that gets the task, for the label in the panel.
    private(set) var noteTitle: String

    @ObservationIgnored private let service: TaskService
    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let targetNote: () throws -> Note
    /// Closes the panel. The controller sets it.
    @ObservationIgnored var onClose: () -> Void = {}

    /// - Parameter targetNote: returns the note that gets the new task, for example `AppCore.quickAddNote`.
    init(service: TaskService, engine: TimerEngine, targetNote: @escaping () throws -> Note) {
        self.service = service
        self.engine = engine
        self.targetNote = targetNote
        noteTitle = (try? targetNote().title) ?? ModelStore.inboxTitle
    }

    var step: QuickAddFlow.Step {
        flow.step
    }

    /// Feeds one event to the flow and runs the effects it returns.
    func send(_ event: QuickAddFlow.Event) {
        for effect in flow.handle(event) {
            run(effect)
        }
    }

    /// The switch question for the active timer at `now`, or nil when no timer is active.
    func switchMessage(at now: Date) -> String? {
        guard let current = engine.activeTimer else {
            return nil
        }
        return SwitchConfirmation.message(
            current: current,
            currentTitle: engine.activeTask?.title ?? "",
            newTitle: flow.taskTitle ?? "",
            now: now
        )
    }

    private func run(_ effect: QuickAddFlow.Effect) {
        switch effect {
        case let .createTask(title):
            createTask(title: title)
        case let .startTimer(seconds, replacing):
            startTimer(seconds: seconds, replacing: replacing)
        case .close:
            onClose()
        }
    }

    private func createTask(title: String) {
        do {
            let note = try targetNote()
            noteTitle = note.title
            task = service.createTask(title: title, in: note)
        } catch {
            Self.logger.error("No note for the new task: \(error.localizedDescription, privacy: .public)")
            send(.focusLost)
        }
    }

    /// Starts the timer. The estimate is set only when the timer really starts, so a cancelled switch leaves the
    /// task as it was.
    private func startTimer(seconds: TimeInterval, replacing: Bool) {
        guard let task else {
            return
        }
        switch engine.start(task: task, seconds: seconds, replacing: replacing) {
        case .started:
            service.setEstimate(seconds, for: task)
            send(.timerStarted)
        case .needsConfirmation:
            send(.engineNeedsConfirmation)
        }
    }
}
