// Last edited: 2026-09-24 20:16 PT

import KeyboardShortcuts
import Observation

/// Turns the two global hotkeys on and off to match `Preferences`: at launch, and at once after each change in
/// Settings. Off unregisters the hotkey (`KeyboardShortcuts.disable`), so the keys go to the app in front again.
///
/// `registerTogglePopover(_:)` connects the open-popover hotkey. `QuickAddController.registerHotkey()` connects the
/// quick-add hotkey.
@MainActor
final class GlobalHotkeys {
    /// Turns one hotkey on or off. The app uses `KeyboardShortcuts`; tests pass a fake.
    typealias SetEnabled = @MainActor (KeyboardShortcuts.Name, Bool) -> Void

    private let preferences: Preferences
    private let setEnabled: SetEnabled

    init(preferences: Preferences, setEnabled: @escaping SetEnabled = GlobalHotkeys.setEnabledInKeyboardShortcuts) {
        self.preferences = preferences
        self.setEnabled = setEnabled
        followPreferences()
    }

    /// Runs `action` when you press the open-popover hotkey. Call it one time, at launch.
    func registerTogglePopover(_ action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .togglePopover, action: action)
    }

    static func setEnabledInKeyboardShortcuts(_ name: KeyboardShortcuts.Name, _ isEnabled: Bool) {
        if isEnabled {
            KeyboardShortcuts.enable(name)
        } else {
            KeyboardShortcuts.disable(name)
        }
    }

    /// Applies the switches now, and again after each change. Observation calls `onChange` before the change, so
    /// the update waits for the next main actor turn, when the new value is in place.
    private func followPreferences() {
        withObservationTracking {
            setEnabled(.quickAdd, preferences.quickAddHotkeyEnabled)
            setEnabled(.togglePopover, preferences.togglePopoverHotkeyEnabled)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followPreferences()
            }
        }
    }
}
