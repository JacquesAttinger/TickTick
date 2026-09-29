// Last edited: 2026-09-29 10:46 PT

import Foundation
import KeyboardShortcuts

/// One section of the Help tab: a title and short paragraphs of plain text.
struct HelpSection: Identifiable {
    let title: String
    let paragraphs: [String]

    var id: String {
        title
    }
}

/// The text of the Help tab, as data, so the tests can check it without a window. The feature sections follow the
/// "Product decisions" in `docs/planning.md`. The shortcut groups come from `ShortcutCatalog`, the list that the key
/// handlers use, so Help cannot show other keys than the app uses.
@MainActor
enum HelpContent {
    /// The feature sections, in order. They read the hotkeys' current keys and the switches in `preferences`, so the
    /// text follows the Shortcuts tab.
    static func sections(preferences: Preferences) -> [HelpSection] {
        [createTask(preferences), timeTask, menuBar, popover(preferences), timeIsUp, notes, settings]
    }

    /// Every shortcut, in one group for each scope.
    static var shortcutGroups: [(scope: ShortcutScope, shortcuts: [ShortcutInfo])] {
        ShortcutCatalog.grouped
    }

    /// Whether the switch of a shortcut on the Shortcuts tab is on. The Notes window keys have no switch, so they are
    /// always on. A hotkey with no keys shows "None" as its keys, not "Off".
    static func isOn(_ info: ShortcutInfo, preferences: Preferences) -> Bool {
        switch info.keys {
        case let .hotkey(name):
            hotkeyIsOn(name, preferences: preferences)
        case .command, .plain:
            info.scope != .popover || preferences.popoverKeysEnabled
        }
    }

    /// A global hotkey for a sentence: its keys, for example `⌃⌥Space`, or where to turn it on when it is off or has
    /// no keys. `title` is the hotkey's section title on the Shortcuts tab, so you can find it there.
    static func hotkeyText(keys: KeyboardShortcuts.Shortcut?, title: String, isOn: Bool) -> String {
        guard isOn else { return "the “\(title)” hotkey (turn it on in the Shortcuts tab)" }
        guard let keys else { return "the “\(title)” hotkey (record its keys in the Shortcuts tab)" }
        return keys.description
    }

    private static func hotkeyIsOn(_ name: KeyboardShortcuts.Name, preferences: Preferences) -> Bool {
        switch name {
        case .quickAdd: preferences.quickAddHotkeyEnabled
        case .togglePopover: preferences.togglePopoverHotkeyEnabled
        default: true
        }
    }

    private static func hotkeyText(_ name: KeyboardShortcuts.Name, title: String, preferences: Preferences) -> String {
        hotkeyText(
            keys: KeyboardShortcuts.getShortcut(for: name),
            title: title,
            isOn: hotkeyIsOn(name, preferences: preferences)
        )
    }

    private static func createTask(_ preferences: Preferences) -> HelpSection {
        let keys = hotkeyText(.quickAdd, title: "Quick add", preferences: preferences)
        return HelpSection(title: "Create a task", paragraphs: [
            "Press \(keys) in any app. Type the task and press Return. Quick add saves the task in the Inbox note.",
            "Then “How long?” asks for a time. Press Return to start the timer, or press Esc to keep the task with "
                + "no timer.",
            "Type 25 for 25 minutes. 90m, 1h, 1h30, and 1:30 also work. You can also click 5, 15, 25, 45, or 60 min. "
                + "The line under the field shows the length and when the timer ends.",
            "In the Notes window, Return on a new task asks “How long?” the same way. The ▶ button on a task starts "
                + "its timer later.",
        ])
    }

    private static var timeTask: HelpSection {
        HelpSection(title: "Time a task", paragraphs: [
            "One timer runs at a time. When you start a second timer, TickTick asks first, for example: "
                + "Stop “A” (12 min left) and start “B”? Click Stop & Start to switch.",
            "The timer follows the real clock. If the time runs out while the Mac sleeps, the alarm starts when the "
                + "Mac wakes.",
            "A timer stays when you quit TickTick or it crashes. Open TickTick again and the timer continues.",
        ])
    }

    private static var menuBar: HelpSection {
        HelpSection(title: "The menu bar", paragraphs: [
            "TickTick is always in the menu bar. It has a Dock icon only while the Notes window or Settings is open.",
            "While a timer runs, the menu bar shows the task and the time left, for example "
                + "⏱ Write cover letter · 24:13. A name longer than 24 characters is cut.",
            "A paused timer shows ⏸ and is dimmed. With no timer, the menu bar shows only ⏱.",
            "After zero, the time turns red and counts up, for example +2:13.",
        ])
    }

    private static func popover(_ preferences: Preferences) -> HelpSection {
        let keys = hotkeyText(.togglePopover, title: "Open the popover", preferences: preferences)
        let singleKeys = preferences.popoverKeysEnabled
            ? "They are in the “In the popover” table below."
            : "They are off now. Turn them on in the Shortcuts tab."
        return HelpSection(title: "The popover", paragraphs: [
            "Click the menu bar item, or press \(keys), to open the popover.",
            "It shows the task, its note (Open ↗ opens the note), the time left, a progress bar, the start and end "
                + "times, the estimate, and the date.",
            "+1m, +5m, and +10m add time. +custom adds a time that you type, for example 2m or 1h30.",
            "Pause stops the clock, and Resume starts it again. Stop ends the timer and keeps the task open. Done ends "
                + "the timer and checks the task.",
            "While the popover is open and a timer is active, single keys work too. \(singleKeys)",
            "Open Notes, Settings…, and Quit TickTick are at the bottom.",
        ])
    }

    private static var timeIsUp: HelpSection {
        HelpSection(title: "When time is up", paragraphs: [
            "A white flash shows on every display 3 times, and the Glass sound plays once. Clicks go through the "
                + "flash. If Reduce Motion is on, you see one slow fade instead.",
            "A notification shows at the top right with Done, +5 min, and Stop buttons.",
            "The menu bar turns red and counts up until you choose Done, +5 min, or Stop.",
            "Focus does not stop the flash or the sound. If you turn off notifications for TickTick, the flash and the "
                + "sound still work.",
        ])
    }

    private static var notes: HelpSection {
        HelpSection(title: "Notes", paragraphs: [
            "Click Open Notes in the popover to open the Notes window.",
            "A note has a title and a list of tasks with checkboxes.",
            "The Inbox note is always first. You can rename it, but you cannot delete it. Quick add puts tasks there.",
            "Drag a task by its handle to move it. A checked task stays in its place with a filled checkbox.",
            "A badge such as ⏱ 45m est · 52m actual shows the time you planned and the time the timer ran. Paused "
                + "time does not count.",
            "Checking the task that has the timer is the same as Done. Deleting it stops the timer.",
        ])
    }

    private static var settings: HelpSection {
        HelpSection(title: "Settings", paragraphs: [
            "Click Settings… in the popover, or press ⌘, while TickTick is in front.",
            "General: Launch at login opens TickTick in the menu bar when you log in to your Mac.",
            "Shortcuts: turn each hotkey on or off and record other keys for it. You can also turn off the popover "
                + "keys.",
            "Help: this page.",
        ])
    }
}
