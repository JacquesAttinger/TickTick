// Last edited: 2026-09-24 15:25 PT

import Foundation
import os

/// The app's long-lived data and timer objects. `AppDelegate` builds one at launch and keeps it while the app runs.
///
/// Launch order: `init` builds the objects. Then the caller connects the timer's listeners (for example the menu bar
/// and `timerEngine.onExpired`). Then `startTimer(launchArguments:)` restores the saved timer, so the listeners see
/// the restored state and an expiry that happened while the app was quit.
@MainActor
final class AppCore {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "AppCore")

    let modelStore: ModelStore
    let taskService: TaskService
    let timerEngine: TimerEngine
    let activeTimerStore: ActiveTimerStore

    /// - Parameters:
    ///   - activeTimerStore: where the timer state is saved. The app uses the standard defaults.
    ///   - schedulesExpiry: true in the app. Tests pass false and a test clock.
    init(
        modelStore: ModelStore,
        activeTimerStore: ActiveTimerStore = ActiveTimerStore(),
        clock: any TimerClock = SystemClock(),
        schedulesExpiry: Bool = true
    ) {
        self.modelStore = modelStore
        self.activeTimerStore = activeTimerStore
        taskService = TaskService(context: modelStore.context, now: { clock.now })
        timerEngine = TimerEngine(service: taskService, clock: clock, schedulesExpiry: schedulesExpiry)
    }

    /// Restores the timer that was saved before the last quit. Then, when the launch arguments have
    /// `-debugStartTimerSeconds N`, starts an N-second debug timer in its place.
    func startTimer(launchArguments: [String: Any]) {
        activeTimerStore.restore(into: timerEngine)
        guard launchArguments[DebugTimerLaunch.argument] != nil else {
            return
        }
        guard let seconds = DebugTimerLaunch.seconds(in: launchArguments) else {
            let value = String(describing: launchArguments[DebugTimerLaunch.argument] ?? "")
            Self.logger.error("-\(DebugTimerLaunch.argument, privacy: .public) \(value, privacy: .public) is ignored")
            return
        }
        do {
            let inbox = try modelStore.bootstrapInbox()
            DebugTimerLaunch.start(seconds: seconds, service: taskService, engine: timerEngine, inbox: inbox)
            Self.logger.notice("Started the debug timer for \(seconds, format: .fixed(precision: 1)) s")
        } catch {
            Self.logger.error("No Inbox for the debug timer: \(error.localizedDescription, privacy: .public)")
        }
    }
}
