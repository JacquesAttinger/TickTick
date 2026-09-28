// Last edited: 2026-09-24 20:16 PT

import Foundation
import Observation

/// The on/off switches of the Settings window (product decision 15b). Each one is on by default and is saved in
/// `UserDefaults` at once. The hotkeys and the popover keys read these values live, so a change needs no relaunch.
@Observable
@MainActor
final class Preferences {
    /// The `UserDefaults` keys.
    enum Key {
        static let quickAddHotkeyEnabled = "quickAddHotkeyEnabled"
        static let togglePopoverHotkeyEnabled = "togglePopoverHotkeyEnabled"
        static let popoverKeysEnabled = "popoverKeysEnabled"
        static let all = [quickAddHotkeyEnabled, togglePopoverHotkeyEnabled, popoverKeysEnabled]
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The global quick-add hotkey (⌃⌥Space by default).
    var quickAddHotkeyEnabled: Bool {
        didSet { defaults.set(quickAddHotkeyEnabled, forKey: Key.quickAddHotkeyEnabled) }
    }

    /// The global hotkey that opens and closes the popover (⌃⌥T by default).
    var togglePopoverHotkeyEnabled: Bool {
        didSet { defaults.set(togglePopoverHotkeyEnabled, forKey: Key.togglePopoverHotkeyEnabled) }
    }

    /// The single keys that work while the popover is open (Space, D, S, 1, 5, 0).
    var popoverKeysEnabled: Bool {
        didSet { defaults.set(popoverKeysEnabled, forKey: Key.popoverKeysEnabled) }
    }

    /// - Parameter defaults: the app uses the standard defaults. Tests pass a scratch suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        quickAddHotkeyEnabled = defaults.object(forKey: Key.quickAddHotkeyEnabled) as? Bool ?? true
        togglePopoverHotkeyEnabled = defaults.object(forKey: Key.togglePopoverHotkeyEnabled) as? Bool ?? true
        popoverKeysEnabled = defaults.object(forKey: Key.popoverKeysEnabled) as? Bool ?? true
    }
}
