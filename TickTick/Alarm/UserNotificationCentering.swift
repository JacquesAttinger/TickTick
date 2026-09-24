// Last edited: 2026-09-24 16:58 PT

import os
import UserNotifications

/// The notification center calls that `NotificationController` uses.
///
/// `UNUserNotificationCenter` conforms. It works only in a signed app, so tests use a fake center instead.
@MainActor
protocol UserNotificationCentering: AnyObject {
    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate)
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    /// Schedules the request, or shows it at once when it has no trigger. A request with the ID of a scheduled one
    /// replaces it.
    func addRequest(_ request: UNNotificationRequest)
    func removePendingRequests(withIdentifiers identifiers: [String])
    /// Removes every scheduled notification and every notification that shows in Notification Center.
    func removeAllRequests()
    /// Removes every notification that shows in Notification Center. Scheduled ones stay.
    func removeAllDelivered()
    /// The IDs of the scheduled notifications that have not fired yet.
    func pendingIdentifiers() async -> [String]
    /// The IDs of the notifications that show in Notification Center.
    func deliveredIdentifiers() async -> [String]
}

extension UNUserNotificationCenter: UserNotificationCentering {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "Notifications")

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }

    func addRequest(_ request: UNNotificationRequest) {
        let identifier = request.identifier
        add(request) { error in
            if let error {
                Self.logger.error("""
                Adding notification \(identifier, privacy: .public) failed: \
                \(error.localizedDescription, privacy: .public)
                """)
            }
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllRequests() {
        removeAllPendingNotificationRequests()
        removeAllDeliveredNotifications()
    }

    func removeAllDelivered() {
        removeAllDeliveredNotifications()
    }

    func pendingIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    func deliveredIdentifiers() async -> [String] {
        await deliveredNotifications().map(\.request.identifier)
    }
}
