// Last edited: 2026-09-24 15:17 PT

import AppKit
import Observation
import os

/// The state machine for the app's one timer: idle, running, paused, or overtime.
///
/// It records each run as a `TimerSession` through `TaskService`. It stores dates, never a tick count,
/// so the UI reads the time left from `state` and the clock, for example with a 1 s refresh.
/// Every operation first calls `checkExpiry()`, so it never acts on a running timer whose end has passed.
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

    /// Called one time when a timer enters overtime, with the timer in its new overtime phase.
    /// This also happens on wake from sleep and on a restore after the end passed while the app was quit.
    @ObservationIgnored var onExpired: ((ActiveTimer) -> Void)?
    /// Called after every state change. `ActiveTimerStore` saves the state here.
    @ObservationIgnored var stateDidChange: ((TimerState) -> Void)?

    let service: TaskService
    let clock: any TimerClock
    private let schedulesExpiry: Bool
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

    /// - Parameter schedulesExpiry: true in the app. The engine then arms a wall-clock `Timer` for the end date
    ///   and checks again when the Mac wakes. Tests leave it false and call `checkExpiry()` themselves.
    init(service: TaskService, clock: any TimerClock, schedulesExpiry: Bool = false) {
        self.service = service
        self.clock = clock
        self.schedulesExpiry = schedulesExpiry
        if schedulesExpiry {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recheckExpiry() }
            }
        }
        service.timerHooks = self
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
        checkExpiry()
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
        checkExpiry()
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

    /// Adds time. While running or paused, the time left grows. In overtime, the timer runs again
    /// with `seconds` left, and the overtime so far stays in the active time.
    func extend(seconds: TimeInterval) {
        checkExpiry()
        guard var timer = activeTimer, seconds > 0 else {
            return
        }
        let now = clock.now
        switch timer.phase {
        case let .running(endDate):
            timer.phase = .running(endDate: endDate.addingTimeInterval(seconds))
            timer.plannedSeconds += seconds
        case let .paused(remaining):
            timer.phase = .paused(remaining: remaining + seconds)
            timer.plannedSeconds += seconds
        case .overtime:
            timer.phase = .running(endDate: now.addingTimeInterval(seconds))
            timer.plannedSeconds = timer.activeSeconds(at: now) + seconds
        }
        setState(.active(timer), event: "extend")
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

    // MARK: - Restore

    /// Puts back a state that was saved before the app quit. Call it one time, at launch, before other operations.
    ///
    /// A running timer whose end passed while the app was quit goes to overtime and calls `onExpired`.
    /// A saved overtime does not call it again, because that alarm fired before the quit.
    /// When the task no longer exists, the engine stays idle and closes the session as `deleted`.
    func restore(_ saved: TimerState) {
        guard let timer = saved.activeTimer else {
            return
        }
        guard service.task(withID: timer.taskID) != nil else {
            closeSession(of: timer, outcome: .deleted)
            setState(.idle, event: "restore without task")
            return
        }
        setState(saved, event: "restore")
        checkExpiry()
    }

    // MARK: - Expiry

    /// Moves a running timer whose end date has passed to overtime, and calls `onExpired`.
    /// The phase change makes sure that this happens only one time for each end date.
    func checkExpiry() {
        guard var timer = activeTimer, case let .running(endDate) = timer.phase, clock.now >= endDate else {
            return
        }
        timer.phase = .overtime(since: endDate)
        setState(.active(timer), event: "expired")
        onExpired?(timer)
    }

    /// Checks expiry, then arms the timer again. The wall-clock `Timer` and the wake observer call this.
    /// A `Timer` can fire a little early, or late after sleep, so it is armed again after each check.
    private func recheckExpiry() {
        checkExpiry()
        updateExpiryTimer()
    }

    /// Arms one `Timer` for the end date of a running timer, and cancels it in every other state.
    private func updateExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        guard schedulesExpiry, case let .running(endDate) = activeTimer?.phase else {
            return
        }
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckExpiry() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
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
        updateExpiryTimer()
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

extension TimerEngine: TaskTimerHooks {
    /// Checking the running task, anywhere in the app, is the same as Done.
    /// `done()` itself goes idle before it checks the task, so this call does nothing then.
    func taskWasCompleted(_ task: TaskItem) {
        guard activeTimer?.taskID == task.id else {
            return
        }
        finish(outcome: .done)
    }

    /// Deleting the running task stops its timer. The session ends as `deleted`.
    func taskWillBeDeleted(_ task: TaskItem) {
        guard activeTimer?.taskID == task.id else {
            return
        }
        finish(outcome: .deleted)
    }
}
