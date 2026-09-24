// Last edited: 2026-09-24 17:08 PT

import Foundation
import Observation
import os
import UserNotifications

/// Connects the alarm to the timer engine.
///
/// When the timer reaches zero, the screens flash, the sound plays, and the banner shows (product decision 11).
/// On every timer change (start, pause, resume, extend, stop, done, and a rename of the task) it schedules or
/// cancels the banner through `NotificationPlanner`.
@MainActor
final class AlarmController {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "Alarm")

    let notifications: NotificationController
    private let engine: TimerEngine
    /// The flash and the sound. Tests count the calls instead.
    private let signal: () -> Void
    /// The banner check of the last expiry. Tests wait for it.
    private(set) var deliveryCheck: Task<Void, Never>?

    /// Takes over `engine.onExpired`. Build it before the saved timer is restored, so an expiry during the restore
    /// fires the alarm.
    init(engine: TimerEngine, notifications: NotificationController, signal: @escaping () -> Void) {
        self.engine = engine
        self.notifications = notifications
        self.signal = signal
        engine.onExpired = { [weak self] timer in
            self?.fire(for: timer)
        }
    }

    /// The app's alarm: the real notification center, the flash, and the "Glass" sound. It registers the banner
    /// buttons and asks for permission at once.
    static func makeForApp(engine: TimerEngine) -> AlarmController {
        let flash = FlashController()
        let sound = AlarmSound()
        let notifications = NotificationController(center: UNUserNotificationCenter.current(), engine: engine)
        notifications.start()
        return AlarmController(engine: engine, notifications: notifications) {
            flash.flash()
            sound.play()
        }
    }

    /// Schedules the banner for the current timer, and again after each change.
    /// Call it after the saved timer is restored: the first decision then fits the restored timer, so a banner
    /// that the system showed while the app was quit stays.
    func startSyncingNotifications() {
        let decision = withObservationTracking {
            NotificationPlanner.plan(
                for: engine.state,
                taskName: engine.activeTask?.title ?? "",
                now: engine.clock.now
            )
        } onChange: { [weak self] in
            // Observation calls this before the change. The next main actor turn sees the new state.
            Task { @MainActor in
                self?.startSyncingNotifications()
            }
        }
        notifications.apply(decision)
    }

    private func fire(for timer: ActiveTimer) {
        Self.logger.notice("Alarm fired for session \(timer.sessionID, privacy: .public)")
        signal()
        let taskName = engine.activeTask?.title ?? ""
        deliveryCheck = Task {
            await notifications.ensureDelivered(for: timer, taskName: taskName)
        }
    }
}
