// Last edited: 2026-09-24 15:20 PT

import Foundation
import Testing
@testable import TickTick

/// A saved-timer key that only one test uses. All tests share one defaults suite (one plist file in
/// `~/Library/Preferences`), so a test run does not leave a new file behind. The key goes away with this object.
@MainActor
final class TestTimerDefaults {
    private nonisolated static let suiteName = "com.jacquesattinger.TickTickTests"

    let defaults: UserDefaults
    let key = "activeTimer.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: Self.suiteName))
    }

    deinit {
        UserDefaults(suiteName: Self.suiteName)?.removeObject(forKey: key)
    }

    /// A store on this key. Stores made from one `TestTimerDefaults` share the saved state, as after a relaunch.
    func makeStore() -> ActiveTimerStore {
        ActiveTimerStore(defaults: defaults, key: key)
    }

    /// The saved JSON text, or nil when nothing is saved.
    var savedText: String? {
        defaults.string(forKey: key)
    }
}
