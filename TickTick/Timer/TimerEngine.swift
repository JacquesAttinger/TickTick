// Last edited: 2026-09-24 15:13 PT

import Foundation
import Observation
import os

/// The state machine for the app's one timer: idle, running, paused, or overtime.
///
/// It records each run as a `TimerSession` through `TaskService`. It stores dates, never a tick count,
/// so the UI reads the time left from `state` and the clock, for example with a 1 s refresh.
@Observable
@MainActor
final class TimerEngine {
    enum StartResult: Equatable {
        case started
        /// Another timer is active, and nothing changed. Call `start` again with `replacing: true` to switch.
        case needsConfirmation(current: ActiveTimer)
    }

    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "TimerEngine")

    private(set) var state: TimerState = .idle

    /// Called after every state change. `ActiveTimerStore` saves the state here.
    @ObservationIgnored var stateDidChange: ((TimerState) -> Void)?

    let service: TaskService
    let clock: any TimerClock

    init(service: TaskService, clock: any TimerClock) {
        self.service = service
        self.clock = clock
    }

    /// The active timer, or nil when idle.
    var activeTimer: ActiveTimer? {
        state.activeTimer
    }

    /// The task of the active timer. It is looked up by ID, so a rename shows at once.
    var activeTask: TaskItem? {
        activeTimer.flatMap { service.task(withID: $0.taskID) }
    }

    // MARK: - Operations

    /// Starts a `seconds` timer on `task`. When a timer is already active, this changes nothing and asks for
    /// confirmation, unless `replacing` is true: then the old session ends as `replaced` first.
    @discardableResult
    func start(task: TaskItem, seconds: TimeInterval, replacing: Bool = false) -> StartResult {
        if let current = activeTimer {
            guard replacing else {
                return .needsConfirmation(current: current)
            }
            closeSession(of: current, outcome: .replaced)
        }
        let now = clock.now
        let session = service.startSession(for: task, plannedSeconds: seconds, at: now)
        let timer = ActiveTimer(
            taskID: task.id,
            sessionID: session.id,
            plannedSeconds: seconds,
            startedAt: now,
            accumulatedActiveSeconds: 0,
            lastResumedAt: now,
            phase: .running(endDate: now.addingTimeInterval(seconds))
        )
        setState(.active(timer), event: "start")
        return .started
    }

    /// Pauses a running timer and keeps its remaining time. Does nothing in any other phase.
    func pause() {
        guard var timer = activeTimer, case let .running(endDate) = timer.phase else {
            return
        }
        let now = clock.now
        timer.accumulatedActiveSeconds = timer.activeSeconds(at: now)
        timer.lastResumedAt = nil
        timer.phase = .paused(remaining: max(0, endDate.timeIntervalSince(now)))
        setState(.active(timer), event: "pause")
    }

    /// Runs a paused timer again with the time it had left. Does nothing in any other phase.
    func resume() {
        guard var timer = activeTimer, case let .paused(remaining) = timer.phase else {
            return
        }
        let now = clock.now
        timer.lastResumedAt = now
        timer.phase = .running(endDate: now.addingTimeInterval(remaining))
        setState(.active(timer), event: "resume")
    }

    /// Ends the timer and keeps the task open. The session ends as `stopped`.
    func stop() {
        finish(outcome: .stopped)
    }

    /// Ends the timer and checks the task. The session ends as `done`.
    func done() {
        guard let timer = finish(outcome: .done),
              let task = service.task(withID: timer.taskID),
              !task.isDone
        else {
            return
        }
        service.toggleDone(task)
    }

    // MARK: - State changes

    /// Closes the active timer's session with `outcome` and goes idle. Returns the timer that ended.
    @discardableResult
    private func finish(outcome: SessionOutcome) -> ActiveTimer? {
        guard let timer = activeTimer else {
            return nil
        }
        closeSession(of: timer, outcome: outcome)
        setState(.idle, event: outcome.rawValue)
        return timer
    }

    private func closeSession(of timer: ActiveTimer, outcome: SessionOutcome) {
        guard let session = service.session(withID: timer.sessionID) else {
            Self.logger.error("Session \(timer.sessionID, privacy: .public) is missing, so it cannot be closed")
            return
        }
        let now = clock.now
        service.closeSession(
            session,
            endedAt: now,
            activeSeconds: timer.activeSeconds(at: now),
            plannedSeconds: timer.plannedSeconds,
            outcome: outcome
        )
    }

    private func setState(_ newState: TimerState, event: String) {
        state = newState
        log(event)
        stateDidChange?(newState)
    }

    /// Writes one line per change, so `log show --predicate 'subsystem == "com.jacquesattinger.TickTick"'`
    /// shows what the timer did.
    private func log(_ event: String) {
        guard let timer = activeTimer else {
            Self.logger.notice("\(event, privacy: .public): idle")
            return
        }
        let now = clock.now
        let phase = switch timer.phase {
        case .running: "running"
        case .paused: "paused"
        case .overtime: "overtime"
        }
        Self.logger.notice("""
        \(event, privacy: .public): \(phase, privacy: .public), \
        remaining \(timer.remaining(at: now)) s, overtime \(timer.overtime(at: now)) s, \
        active \(timer.activeSeconds(at: now)) s, planned \(timer.plannedSeconds) s, \
        task \(timer.taskID, privacy: .public), session \(timer.sessionID, privacy: .public)
        """)
    }
}
