// Last edited: 2026-09-24 20:16 PT

import KeyboardShortcuts
import SwiftUI
import Testing
@testable import TickTick

@MainActor
struct ShortcutCatalogTests {
    @Test("Catalog ids are unique")
    func idsAreUnique() {
        let ids = ShortcutCatalog.all.map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test("Every catalog entry has a description and keys")
    func everyEntryHasADescription() {
        for info in ShortcutCatalog.all {
            #expect(!info.description.trimmingCharacters(in: .whitespaces).isEmpty, "\(info.id)")
            #expect(!info.keysText.isEmpty, "\(info.id)")
        }
    }

    @Test("Both global hotkeys and all six popover keys are in the catalog")
    func globalAndPopoverEntriesArePresent() {
        let ids = Set(ShortcutCatalog.all.map(\.id))
        #expect(ids.contains("global.quickAdd"))
        #expect(ids.contains("global.togglePopover"))

        let popoverKeys = ShortcutCatalog.all.filter { $0.scope == .popover }.map(\.keysText)
        #expect(popoverKeys == ["Space", "D", "S", "1", "5", "0"])
    }

    @Test("Each scope has entries, in the order global, popover, notes")
    func scopesInOrder() {
        let scopes = ShortcutCatalog.all.map(\.scope)

        #expect(Set(scopes) == Set(ShortcutScope.allCases))
        #expect(scopes == scopes.sorted { order($0) < order($1) })
    }

    @Test("The global hotkeys start as ⌃⌥Space and ⌃⌥T")
    func hotkeyDefaults() {
        #expect(KeyboardShortcuts.Name.quickAdd.initialShortcut == .init(.space, modifiers: [.control, .option]))
        #expect(KeyboardShortcuts.Name.togglePopover.initialShortcut == .init(.t, modifiers: [.control, .option]))
    }

    @Test("Notes shortcuts show their keys as Mac symbols, in the order ⌃⌥⇧⌘")
    func notesSymbols() {
        #expect(ShortcutCatalog.newNote.keysText == "⌘N")
        #expect(ShortcutCatalog.startTimer.keysText == "⌘↩")
        #expect(ShortcutCatalog.markDone.keysText == "⇧⌘C")
        #expect(ShortcutCatalog.symbols(for: KeyboardShortcut(.space, modifiers: [.command, .option, .control])) ==
            "⌃⌥⌘Space")
    }

    private func order(_ scope: ShortcutScope) -> Int {
        ShortcutScope.allCases.firstIndex(of: scope) ?? 0
    }
}
