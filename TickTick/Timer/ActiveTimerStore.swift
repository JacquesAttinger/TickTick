// Last edited: 2026-09-24 15:17 PT

import Foundation
import os

/// Saves the timer state to `UserDefaults` on every change and gives it back at launch,
/// so an active timer survives a quit or a crash.
///
/// The state is JSON text under the key `activeTimer`, so
/// `defaults read com.jacquesattinger.TickTick activeTimer` shows it. Dates are seconds since 2001-01-01.
@MainActor
final class ActiveTimerStore {
    static let defaultKey = "activeTimer"
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "ActiveTimerStore")

    private let defaults: UserDefaults
    private let key: String

    /// - Parameter key: the app uses the default. Tests pass their own key, so they never share a saved state.
    init(defaults: UserDefaults = .standard, key: String = ActiveTimerStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Gives the saved state to the engine, then saves every later change.
    /// Set `engine.onExpired` before this call: a timer whose end passed while the app was quit calls it here.
    /// The engine keeps this store alive through its `stateDidChange` closure.
    func restore(into engine: TimerEngine) {
        engine.stateDidChange = { state in
            self.save(state)
        }
        engine.restore(load())
    }

    /// The saved state. Idle when nothing is saved, or when the saved text cannot be read.
    func load() -> TimerState {
        guard let json = defaults.string(forKey: key) else {
            return .idle
        }
        do {
            return try JSONDecoder().decode(TimerState.self, from: Data(json.utf8))
        } catch {
            let reason = error.localizedDescription
            Self.logger.error("The saved timer cannot be read, so it is dropped: \(reason, privacy: .public)")
            defaults.removeObject(forKey: key)
            return .idle
        }
    }

    /// Saves an active timer. Removes the key when the timer is idle.
    func save(_ state: TimerState) {
        guard state.activeTimer != nil else {
            defaults.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let json = try String(data: encoder.encode(state), encoding: .utf8)
            defaults.set(json, forKey: key)
        } catch {
            Self.logger.error("Saving the timer failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
