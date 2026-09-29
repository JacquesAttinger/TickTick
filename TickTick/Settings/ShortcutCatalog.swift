// Last edited: 2026-09-29 10:35 PT

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// The global quick-add hotkey, ⌃⌥Space by default (product decision 15).
    static let quickAdd = Self("quickAdd", initial: .init(.space, modifiers: [.control, .option]))
    /// The global hotkey that opens or closes the popover, ⌃⌥T by default (product decision 15).
    static let togglePopover = Self("togglePopover", initial: .init(.t, modifiers: [.control, .option]))
}

/// Where a shortcut works.
enum ShortcutScope: CaseIterable {
    /// From any app.
    case global
    /// While the popover is open and a timer is active.
    case popover
    /// In the Notes window.
    case notes

    /// The heading for this scope's shortcuts in the Help tab.
    var title: String {
        switch self {
        case .global: "Anywhere"
        case .popover: "In the popover"
        case .notes: "In the Notes window"
        }
    }
}

/// One shortcut: its keys, what it does, and where it works.
struct ShortcutInfo: Identifiable {
    enum Keys {
        /// A global hotkey. You can record other keys for it in Settings, so its text is the current keys.
        case hotkey(KeyboardShortcuts.Name)
        /// A key with modifiers that a SwiftUI control uses through `.keyboardShortcut`.
        case command(KeyboardShortcut)
        /// Keys that are shown as they are, for example `Space` or `↑ / ↓`.
        case plain(String)
    }

    /// Stable, for example `global.quickAdd`.
    let id: String
    let keys: Keys
    /// What the shortcut does, in plain words.
    let description: String
    let scope: ShortcutScope

    /// The keys as text, for example `⌃⌥Space`, `⇧⌘C`, or `D`. A hotkey with no keys shows "None".
    @MainActor var keysText: String {
        switch keys {
        case let .hotkey(name): KeyboardShortcuts.getShortcut(for: name)?.description ?? "None"
        case let .command(shortcut): ShortcutCatalog.symbols(for: shortcut)
        case let .plain(text): text
        }
    }
}

/// The one list of every shortcut in the app. The key handlers read their keys from here, and the Help tab
/// (TT-12) shows this list, so the two cannot disagree.
@MainActor
enum ShortcutCatalog {
    // MARK: - Global

    static let quickAdd = ShortcutInfo(
        id: "global.quickAdd",
        keys: .hotkey(.quickAdd),
        description: "Add a task from any app: type the task, then how long it takes",
        scope: .global
    )

    static let togglePopover = ShortcutInfo(
        id: "global.togglePopover",
        keys: .hotkey(.togglePopover),
        description: "Open or close the timer popover from any app",
        scope: .global
    )

    // MARK: - Popover

    /// One entry for each `PopoverKeyCommand`, the list that `PopoverKeyMonitor` uses.
    static let popoverKeys: [ShortcutInfo] = PopoverKeyCommand.allCases.map { command in
        ShortcutInfo(
            id: "popover.\(command)",
            keys: .plain(command.keyName),
            description: command.description,
            scope: .popover
        )
    }

    // MARK: - Notes window

    /// The keys of the controls in the Notes window. The controls read them from here.
    static let newNoteKeys = KeyboardShortcut("n", modifiers: .command)
    static let startTimerKeys = KeyboardShortcut(.return, modifiers: .command)
    static let markDoneKeys = KeyboardShortcut("c", modifiers: [.command, .shift])

    static let newNote = ShortcutInfo(
        id: "notes.newNote",
        keys: .command(newNoteKeys),
        description: "Make a new note",
        scope: .notes
    )

    static let startTimer = ShortcutInfo(
        id: "notes.startTimer",
        keys: .command(startTimerKeys),
        description: "Start a timer on the selected task",
        scope: .notes
    )

    static let markDone = ShortcutInfo(
        id: "notes.markDone",
        keys: .command(markDoneKeys),
        description: "Check the selected task. For the task with the timer, this is the same as Done",
        scope: .notes
    )

    static let notesKeys: [ShortcutInfo] = [
        newNote,
        ShortcutInfo(
            id: "notes.saveTask",
            keys: .plain("Return"),
            description: "Save the task, then ask how long it takes. In “How long?”, start the timer",
            scope: .notes
        ),
        ShortcutInfo(
            id: "notes.skipTimer",
            keys: .plain("Esc"),
            description: "In “How long?”, keep the task with no timer",
            scope: .notes
        ),
        startTimer,
        markDone,
        ShortcutInfo(
            id: "notes.moveBetweenTasks",
            keys: .plain("↑ / ↓"),
            description: "Go to the task above or below",
            scope: .notes
        ),
        ShortcutInfo(
            id: "notes.deleteEmptyTask",
            keys: .plain("⌫"),
            description: "In an empty task, delete it and go to the task above",
            scope: .notes
        ),
    ]

    /// Every shortcut, grouped by scope: global, then popover, then notes.
    static var all: [ShortcutInfo] {
        [quickAdd, togglePopover] + popoverKeys + notesKeys
    }

    /// Every shortcut, in one group for each scope, in the order global, popover, notes. Each group keeps the order of
    /// `all`.
    static var grouped: [(scope: ShortcutScope, shortcuts: [ShortcutInfo])] {
        let entries = all
        return ShortcutScope.allCases.map { scope in (scope, entries.filter { $0.scope == scope }) }
    }

    /// The symbols of a SwiftUI shortcut in the Mac order (⌃⌥⇧⌘), for example `⇧⌘C` or `⌘↩`.
    static func symbols(for shortcut: KeyboardShortcut) -> String {
        let modifiers: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let prefix = modifiers.filter { shortcut.modifiers.contains($0.0) }.map(\.1).joined()
        return prefix + keyName(shortcut.key)
    }

    private static func keyName(_ key: KeyEquivalent) -> String {
        switch key {
        case .return: "↩"
        case .space: "Space"
        case .escape: "Esc"
        case .delete: "⌫"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        default: String(key.character).uppercased()
        }
    }
}
