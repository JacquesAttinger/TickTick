// Last edited: 2026-09-24 17:02 PT

import Foundation
@testable import TickTick
import UserNotifications

/// A notification center in memory, for tests. A request with a trigger waits in `pending` until `fire(_:)`;
/// a request without a trigger goes to `delivered` at once, as in the real center.
@MainActor
final class FakeNotificationCenter: UserNotificationCentering {
    private(set) var delegate: (any UNUserNotificationCenterDelegate)?
    private(set) var categories: Set<UNNotificationCategory> = []
    private(set) var authorizationRequests: [UNAuthorizationOptions] = []
    /// Every request that was added, in order.
    private(set) var added: [UNNotificationRequest] = []
    private(set) var pending: [UNNotificationRequest] = []
    private(set) var delivered: [UNNotificationRequest] = []
    /// Runs at the start of each ID query, so a test can change the timer while a check waits.
    var beforeQuery: (() -> Void)?

    func setDelegate(_ delegate: any UNUserNotificationCenterDelegate) {
        self.delegate = delegate
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests.append(options)
        return true
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        self.categories = categories
    }

    func addRequest(_ request: UNNotificationRequest) {
        added.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        if request.trigger == nil {
            delivered.removeAll { $0.identifier == request.identifier }
            delivered.append(request)
        } else {
            pending.append(request)
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func removeAllRequests() {
        pending = []
        delivered = []
    }

    func removeAllDelivered() {
        delivered = []
    }

    func pendingIdentifiers() async -> [String] {
        beforeQuery?()
        return pending.map(\.identifier)
    }

    func deliveredIdentifiers() async -> [String] {
        beforeQuery?()
        return delivered.map(\.identifier)
    }

    /// Shows a scheduled request, as the system does at its fire date.
    func fire(_ identifier: String) {
        guard let index = pending.firstIndex(where: { $0.identifier == identifier }) else {
            return
        }
        delivered.append(pending.remove(at: index))
    }
}
