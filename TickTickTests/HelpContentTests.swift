// Last edited: 2026-09-29 10:40 PT

import Foundation
import KeyboardShortcuts
import Testing
@testable import TickTick

@MainActor
struct HelpContentTests {
    /// `Preferences` on a scratch suite of its own, so the tests can run at the same time as `PreferencesTests`.
    private let suiteName = "com.jacquesattinger.TickTickTests.help.\(UUID().uuidString)"
    private let preferences: Preferences

    init() throws {
        preferences = try Preferences(defaults: #require(UserDefaults(suiteName: suiteName)))
    }

    @Test("Help has the seven feature sections, in order")
    func sectionTitles() {
        #expect(HelpContent.sections(preferences: preferences).map(\.title) == [
            "Create a task",
            "Time a task",
            "The menu bar",
            "The popover",
            "When time is up",
            "Notes",
            "Settings",
        ])
    }

    @Test("Every feature section has text")
    func everySectionHasText() {
        for section in HelpContent.sections(preferences: preferences) {
            #expect(!section.paragraphs.isEmpty, "\(section.title)")
            for paragraph in section.paragraphs {
                #expect(!paragraph.trimmingCharacters(in: .whitespaces).isEmpty, "\(section.title)")
            }
        }
    }

    @Test("The shortcut groups show every catalog entry, once, with a group for each scope")
    func shortcutGroupsCoverTheCatalog() {
        let groups = HelpContent.shortcutGroups

        #expect(groups.flatMap(\.shortcuts).map(\.id) == ShortcutCatalog.all.map(\.id))
        #expect(groups.map(\.scope) == ShortcutScope.allCases)
    }

    @Test("The hotkey text is the keys, or says where to turn the hotkey on or record its keys")
    func hotkeyText() {
        let keys = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])

        #expect(HelpContent.hotkeyText(keys: keys, title: "Quick add", isOn: true) == keys.description)
        #expect(HelpContent.hotkeyText(keys: nil, title: "Quick add", isOn: true) ==
            "the Quick add hotkey (record its keys in the Shortcuts tab)")
        #expect(HelpContent.hotkeyText(keys: keys, title: "Quick add", isOn: false) ==
            "the Quick add hotkey (turn it on in the Shortcuts tab)")
    }

    @Test("A hotkey that is off is off in Help, and the text does not tell you to press it")
    func hotkeyOff() {
        preferences.quickAddHotkeyEnabled = false
        let text = HelpContent.sections(preferences: preferences).flatMap(\.paragraphs)

        #expect(!HelpContent.isOn(ShortcutCatalog.quickAdd, preferences: preferences))
        let off = "Press the Quick add hotkey (turn it on in the Shortcuts tab) in any app."
        #expect(text.contains { $0.hasPrefix(off) })
    }

    @Test("Popover keys that are off are off in Help, and the other scopes stay on")
    func popoverKeysOff() {
        preferences.popoverKeysEnabled = false
        let text = HelpContent.sections(preferences: preferences).flatMap(\.paragraphs)

        #expect(ShortcutCatalog.popoverKeys.allSatisfy { !HelpContent.isOn($0, preferences: preferences) })
        #expect(ShortcutCatalog.notesKeys.allSatisfy { HelpContent.isOn($0, preferences: preferences) })
        #expect(text.contains { $0.hasSuffix("They are off now. Turn them on in the Shortcuts tab.") })
    }

    @Test("With the switches on, the text shows the hotkeys' current keys")
    func sectionsUseCurrentKeys() {
        let text = HelpContent.sections(preferences: preferences).flatMap(\.paragraphs)
        let quickAdd = KeyboardShortcuts.getShortcut(for: .quickAdd)
        let togglePopover = KeyboardShortcuts.getShortcut(for: .togglePopover)
        let quickAddText = HelpContent.hotkeyText(keys: quickAdd, title: "Quick add", isOn: true)
        let togglePopoverText = HelpContent.hotkeyText(keys: togglePopover, title: "Open the popover", isOn: true)

        #expect(text.contains { $0.hasPrefix("Press \(quickAddText) in any app.") })
        #expect(text.contains { $0.contains("press \(togglePopoverText),") })
        #expect(text.contains { $0.hasSuffix("single keys work too. They are in the table below.") })
    }

    @Test("Settings has a Help tab after General and Shortcuts")
    func settingsHasAHelpTab() {
        #expect(SettingsTab.allCases == [.general, .shortcuts, .help])
        #expect(SettingsTab.help.title == "Help")
        #expect(SettingsTab.help.symbolName == "questionmark.circle")
    }
}
