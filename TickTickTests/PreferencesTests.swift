// Last edited: 2026-09-29 10:47 PT

import Foundation
import KeyboardShortcuts
import Testing
@testable import TickTick

/// A fixed test defaults suite, with the `Preferences` keys removed before and after each test.
final class TestPreferenceDefaults {
    let defaults: UserDefaults

    /// - Parameter suiteName: a suite for each test struct, so two structs that run at the same time do not share keys.
    init(suiteName: String = "com.jacquesattinger.TickTickTests") throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        clear()
    }

    deinit {
        clear()
    }

    private func clear() {
        for key in Preferences.Key.all {
            defaults.removeObject(forKey: key)
        }
    }
}

/// `Preferences` has fixed keys, so these tests run one at a time.
@Suite(.serialized)
@MainActor
struct PreferencesTests {
    private let scratch: TestPreferenceDefaults
    private let applied = AppliedStates()

    init() throws {
        scratch = try TestPreferenceDefaults()
    }

    @Test("Every switch is on when nothing is saved yet")
    func defaultsAreOn() {
        let preferences = Preferences(defaults: scratch.defaults)

        #expect(preferences.quickAddHotkeyEnabled)
        #expect(preferences.togglePopoverHotkeyEnabled)
        #expect(preferences.popoverKeysEnabled)
    }

    @Test("A change is saved at once, and a new Preferences (a relaunch) reads it back")
    func writeRoundTrips() {
        let preferences = Preferences(defaults: scratch.defaults)

        preferences.quickAddHotkeyEnabled = false
        preferences.popoverKeysEnabled = false

        #expect(scratch.defaults.object(forKey: Preferences.Key.quickAddHotkeyEnabled) as? Bool == false)
        let relaunched = Preferences(defaults: scratch.defaults)
        #expect(!relaunched.quickAddHotkeyEnabled)
        #expect(relaunched.togglePopoverHotkeyEnabled)
        #expect(!relaunched.popoverKeysEnabled)
    }

    @Test("A switch turned off and on again is saved as on")
    func switchBackOnIsSaved() {
        let preferences = Preferences(defaults: scratch.defaults)

        preferences.togglePopoverHotkeyEnabled = false
        preferences.togglePopoverHotkeyEnabled = true

        #expect(Preferences(defaults: scratch.defaults).togglePopoverHotkeyEnabled)
    }

    // MARK: - GlobalHotkeys

    @Test("At launch, each hotkey gets the saved on/off state")
    func appliesSavedStateAtLaunch() {
        let preferences = Preferences(defaults: scratch.defaults)
        preferences.quickAddHotkeyEnabled = false

        let hotkeys = makeHotkeys(preferences)

        #expect(applied.states[.quickAdd] == false)
        #expect(applied.states[.togglePopover] == true)
        withExtendedLifetime(hotkeys) {}
    }

    @Test("A switch change turns its hotkey off and on at once, with no relaunch")
    func followsChanges() async {
        let preferences = Preferences(defaults: scratch.defaults)
        let hotkeys = makeHotkeys(preferences)

        preferences.togglePopoverHotkeyEnabled = false
        await applied.waitUntil { $0[.togglePopover] == false }
        #expect(applied.states[.togglePopover] == false)
        #expect(applied.states[.quickAdd] == true)

        preferences.togglePopoverHotkeyEnabled = true
        await applied.waitUntil { $0[.togglePopover] == true }
        #expect(applied.states[.togglePopover] == true)
        withExtendedLifetime(hotkeys) {}
    }

    private func makeHotkeys(_ preferences: Preferences) -> GlobalHotkeys {
        GlobalHotkeys(preferences: preferences) { [applied] name, isEnabled in
            applied.states[name] = isEnabled
        }
    }
}

/// The last on/off state that `GlobalHotkeys` set for each hotkey.
@MainActor
private final class AppliedStates {
    var states: [KeyboardShortcuts.Name: Bool] = [:]

    /// Gives the main actor a few turns, for the Observation update that `GlobalHotkeys` schedules.
    func waitUntil(_ condition: ([KeyboardShortcuts.Name: Bool]) -> Bool) async {
        for _ in 0 ..< 20 where !condition(states) {
            await Task.yield()
        }
    }
}
