// Last edited: 2026-09-24 20:16 PT

import Observation
import os
import ServiceManagement

/// The parts of `SMAppService` that `LaunchAtLoginModel` uses. Tests pass a fake.
@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// The "Launch at login" switch. It always shows the real state of the login item (`SMAppService.mainApp`), which
/// you can also change in System Settings → General → Login Items. So the Settings window reads it again each time
/// it comes to the front (`refresh()`).
@Observable
@MainActor
final class LaunchAtLoginModel {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "LaunchAtLogin")

    private(set) var status: SMAppService.Status
    /// Why the last change failed, or nil. The switch then shows the real state again.
    private(set) var errorText: String?
    @ObservationIgnored private let service: any LoginItemService

    /// - Parameter service: the app uses `SMAppService.mainApp`.
    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    /// On when TickTick opens at login, and also while the login item waits for your approval in System Settings,
    /// so you can turn it off again here.
    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// The login item is registered, but System Settings must allow it first.
    var needsApproval: Bool {
        status == .requiresApproval
    }

    /// Registers or unregisters the login item. On an error, the switch goes back to the real state and the
    /// error text shows under it.
    func setOn(_ isOn: Bool) {
        do {
            if isOn {
                try service.register()
            } else {
                try service.unregister()
            }
            errorText = nil
        } catch {
            let text = error.localizedDescription
            errorText = text
            Self.logger.error("Launch at login \(isOn ? "on" : "off") failed: \(text, privacy: .public)")
        }
        refresh()
        let statusName = Self.name(of: status)
        Self.logger.notice("Launch at login set \(isOn ? "on" : "off"): status \(statusName, privacy: .public)")
    }

    /// Reads the state again, for a change made in System Settings.
    func refresh() {
        status = service.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func name(of status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        @unknown default: "unknown"
        }
    }
}
