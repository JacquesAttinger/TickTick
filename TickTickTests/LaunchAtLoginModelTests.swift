// Last edited: 2026-09-24 20:16 PT

import Foundation
import ServiceManagement
import Testing
@testable import TickTick

private struct RegistrationError: LocalizedError {
    var errorDescription: String? {
        "The operation could not be completed."
    }
}

/// A login item that lives only in memory. It never touches the real login items.
@MainActor
private final class FakeLoginItemService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    /// The status that `register()` sets, for example `.requiresApproval`.
    var statusAfterRegister: SMAppService.Status = .enabled
    var error: (any Error)?
    private(set) var calls: [String] = []

    func register() throws {
        calls.append("register")
        if let error {
            throw error
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if let error {
            throw error
        }
        status = .notRegistered
    }
}

@MainActor
struct LaunchAtLoginModelTests {
    private let service = FakeLoginItemService()

    @Test("The switch shows the real state at start")
    func readsStatusAtStart() {
        service.status = .enabled

        let model = LaunchAtLoginModel(service: service)

        #expect(model.isOn)
    }

    @Test("On registers the login item, and off unregisters it")
    func onAndOff() {
        let model = LaunchAtLoginModel(service: service)
        #expect(!model.isOn)

        model.setOn(true)
        #expect(model.isOn)
        #expect(model.status == .enabled)

        model.setOn(false)
        #expect(!model.isOn)
        #expect(service.calls == ["register", "unregister"])
    }

    @Test("A failed change shows the error, and the switch goes back to the real state")
    func errorRevertsTheSwitch() {
        service.error = RegistrationError()
        let model = LaunchAtLoginModel(service: service)

        model.setOn(true)

        #expect(!model.isOn)
        #expect(model.errorText == "The operation could not be completed.")
    }

    @Test("The next change that works clears the error")
    func successClearsTheError() {
        service.error = RegistrationError()
        let model = LaunchAtLoginModel(service: service)
        model.setOn(true)

        service.error = nil
        model.setOn(true)

        #expect(model.isOn)
        #expect(model.errorText == nil)
    }

    @Test("A login item that waits for approval shows as on, with the approval hint")
    func requiresApproval() {
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLoginModel(service: service)

        model.setOn(true)

        #expect(model.isOn)
        #expect(model.needsApproval)
    }

    @Test("refresh reads a change made in System Settings")
    func refreshReadsOutsideChange() {
        service.status = .enabled
        let model = LaunchAtLoginModel(service: service)

        service.status = .notRegistered
        model.refresh()

        #expect(!model.isOn)
    }
}
