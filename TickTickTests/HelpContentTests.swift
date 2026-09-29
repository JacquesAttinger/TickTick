// Last edited: 2026-09-29 10:40 PT

import Testing
@testable import TickTick

@MainActor
struct HelpContentTests {
    @Test("Help has the seven feature sections, in order")
    func sectionTitles() {
        #expect(HelpContent.sections.map(\.title) == [
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
        for section in HelpContent.sections {
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
        #expect(groups.map(\.shortcuts.count) == [2, 6, 7])
    }

    @Test("The hotkey text is the keys, or points to the Shortcuts tab when there are none")
    func hotkeyText() {
        #expect(HelpContent.hotkeyText(keys: "⌥⌘K", name: "Quick add") == "⌥⌘K")
        #expect(HelpContent.hotkeyText(keys: "None", name: "Quick add") ==
            "the Quick add hotkey (record its keys on the Shortcuts tab)")
    }

    @Test("The sections read the hotkeys' current keys")
    func sectionsUseCurrentKeys() {
        let quickAdd = HelpContent.hotkeyText(keys: ShortcutCatalog.quickAdd.keysText, name: "Quick add")
        let togglePopover = HelpContent.hotkeyText(
            keys: ShortcutCatalog.togglePopover.keysText,
            name: "Open the popover"
        )
        let text = HelpContent.sections.flatMap(\.paragraphs)

        #expect(text.contains { $0.contains("Press \(quickAdd) in any app.") })
        #expect(text.contains { $0.contains("press \(togglePopover),") })
    }
}
