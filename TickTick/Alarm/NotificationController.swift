// Last edited: 2026-09-24 17:08 PT

import Foundation
import os
import UserNotifications

/// The "time is up" banner: permission, the `TIMER_DONE` category with its 3 buttons, the schedule, and the
/// button actions.
///
/// The banner is scheduled with the system ahead of time, so it shows at the end even when the app is quit or the
/// Mac sleeps. Its ID is the timer session's UUID, so a new schedule replaces the old one and it cannot fire twice.
/// The banner has no sound: `AlarmSound` plays the sound in the app, so the sound does not play twice.
@MainActor
final class NotificationController: NSObject {
    /// The banner buttons, in the order the banner shows them.
    enum Action: String, CaseIterable {
        case done = "DONE"
        case extendFiveMinutes = "EXTEND_5_MIN"
        case stop = "STOP"

        var title: String {
            switch self {
            case .done: "Done"
            case .extendFiveMinutes: "+5 min"
            case .stop: "Stop"
            }
        }
    }

    static let categoryIdentifier = "TIMER_DONE"
    static let extendSeconds: TimeInterval = 5 * 60
    /// `.active`, not `.timeSensitive`: the personal team cannot sign the Time Sensitive entitlement.
    /// See README "Known limits".
    static let interruptionLevel = UNNotificationInterruptionLevel.active
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "Notifications")

    private let center: any UserNotificationCentering
    private let engine: TimerEngine
    private let deliveryCheckDelay: Duration
    /// The last decision that `apply` carried out, so the same decision twice does nothing.
    private var lastDecision: NotificationDecision?
    /// A new value for each schedule or cancel. A slow check that sees a new value stops, because its facts are old.
    private var generation = 0

    /// - Parameter deliveryCheckDelay: how long `ensureDelivered` waits for the system to show the scheduled
    ///   banner before it checks. Tests pass zero.
    init(center: any UserNotificationCentering, engine: TimerEngine, deliveryCheckDelay: Duration = .seconds(2)) {
        self.center = center
        self.engine = engine
        self.deliveryCheckDelay = deliveryCheckDelay
    }

    /// Registers the banner buttons and becomes the center's delegate. Call it before the app finishes launching,
    /// so a button press that launched the app reaches it. Then asks for permission: the system asks the user
    /// only the first time. When the user says no, the flash and the sound still work.
    func start() {
        center.setNotificationCategories([Self.makeCategory()])
        center.setDelegate(self)
        Task {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                Self.logger.notice("Notification permission granted: \(granted)")
            } catch {
                Self.logger.error("Notification permission failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Schedule

    /// Carries out a `NotificationPlanner` decision.
    /// - Returns: for a schedule, the task that removes the scheduled banners of other sessions. Tests wait for it.
    @discardableResult
    func apply(_ decision: NotificationDecision) -> Task<Void, Never>? {
        guard decision != lastDecision else {
            return nil
        }
        lastDecision = decision
        switch decision {
        case .keep:
            return nil
        case .cancel:
            generation += 1
            center.removeAllRequests()
            Self.logger.notice("Notification cancelled")
            return nil
        case let .schedule(id, fireDate, content):
            generation += 1
            // A banner that still shows is old: the timer runs again.
            center.removeAllDelivered()
            // The trigger needs a time above 0. The planner schedules only an end date in the future.
            let seconds = max(0.1, fireDate.timeIntervalSince(engine.clock.now))
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.addRequest(Self.makeRequest(id: id, content: content, trigger: trigger))
            Self.logger.notice("""
            Notification \(id, privacy: .public) scheduled in \(seconds, format: .fixed(precision: 1)) s
            """)
            let current = generation
            return Task {
                await removeOtherPendingRequests(keeping: id, generation: current)
            }
        }
    }

    /// Shows the banner for a timer that just expired, but only when the system did not show it already and does
    /// not still plan to. This covers the Mac waking up late and a permission that came after the schedule,
    /// without a second banner.
    func ensureDelivered(for timer: ActiveTimer, taskName: String) async {
        let id = NotificationPlanner.identifier(for: timer)
        let current = generation
        try? await Task.sleep(for: deliveryCheckDelay)
        let delivered = await center.deliveredIdentifiers()
        let pending = await center.pendingIdentifiers()
        guard current == generation else {
            Self.logger.notice("Notification \(id, privacy: .public) check skipped: the timer changed")
            return
        }
        guard !delivered.contains(id), !pending.contains(id) else {
            Self.logger.notice("Notification \(id, privacy: .public) is shown or scheduled by the system")
            return
        }
        let content = NotificationContent.make(taskName: taskName, plannedSeconds: timer.plannedSeconds)
        center.addRequest(Self.makeRequest(id: id, content: content, trigger: nil))
        Self.logger.notice("Notification \(id, privacy: .public) shown now")
    }

    /// Removes the scheduled banners of other sessions, for example one left from before a relaunch.
    private func removeOtherPendingRequests(keeping id: String, generation current: Int) async {
        let others = await center.pendingIdentifiers().filter { $0 != id }
        guard current == generation, !others.isEmpty else {
            return
        }
        center.removePendingRequests(withIdentifiers: others)
    }

    // MARK: - Actions

    /// Runs a banner button on the timer. A banner of an older timer does nothing.
    /// - Returns: true when the action changed the timer.
    @discardableResult
    func handleAction(_ actionIdentifier: String, notificationID: String) -> Bool {
        // A click on the banner itself, not on a button, has no action here.
        guard let action = Action(rawValue: actionIdentifier) else {
            return false
        }
        guard let timer = engine.activeTimer, NotificationPlanner.identifier(for: timer) == notificationID else {
            Self.logger.notice("Banner button \(action.rawValue, privacy: .public) ignored: its timer ended")
            return false
        }
        Self.logger.notice("Banner button \(action.rawValue, privacy: .public)")
        switch action {
        case .done: engine.done()
        case .extendFiveMinutes: engine.extend(seconds: Self.extendSeconds)
        case .stop: engine.stop()
        }
        return true
    }

    // MARK: - Building blocks

    static func makeCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: Action.allCases.map { UNNotificationAction(identifier: $0.rawValue, title: $0.title) },
            intentIdentifiers: []
        )
    }

    static func makeRequest(
        id: String,
        content: NotificationContent,
        trigger: UNNotificationTrigger?
    ) -> UNNotificationRequest {
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        body.categoryIdentifier = categoryIdentifier
        body.interruptionLevel = interruptionLevel
        body.sound = nil
        return UNNotificationRequest(identifier: id, content: body, trigger: trigger)
    }
}

extension NotificationController: UNUserNotificationCenterDelegate {
    /// Shows the banner also while TickTick is the active app, for example while its popover is open.
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let notificationID = response.notification.request.identifier
        await handleAction(actionIdentifier, notificationID: notificationID)
    }
}
