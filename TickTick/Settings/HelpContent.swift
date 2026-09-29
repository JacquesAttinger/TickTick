// Last edited: 2026-09-29 10:40 PT

import Foundation

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
    /// The feature sections, in order. They read the hotkeys' current keys, so a new recording shows here too.
    static var sections: [HelpSection] {
        [createTask, timeTask, menuBar, popover, timeIsUp, notes, settings]
    }

    /// Every shortcut, in one group for each scope.
    static var shortcutGroups: [(scope: ShortcutScope, shortcuts: [ShortcutInfo])] {
        ShortcutCatalog.grouped
    }

    /// The keys of a global hotkey for a sentence, for example `⌃⌥Space`. With no keys (`keysText` is "None"), it
    /// points to the Shortcuts tab.
    static func hotkeyText(keys: String, name: String) -> String {
        keys == "None" ? "the \(name) hotkey (record its keys on the Shortcuts tab)" : keys
    }

    private static var quickAddKeys: String {
        hotkeyText(keys: ShortcutCatalog.quickAdd.keysText, name: "Quick add")
    }

    private static var togglePopoverKeys: String {
        hotkeyText(keys: ShortcutCatalog.togglePopover.keysText, name: "Open the popover")
    }

    private static var createTask: HelpSection {
        HelpSection(title: "Create a task", paragraphs: [
            "Press \(quickAddKeys) in any app. Type the task and press Return. "
                + "Quick add saves the task in the Inbox note.",
            "Then \"How long?\" asks for a time. Press Return to start the timer, or press Esc to keep the task with "
                + "no timer.",
            "Type 25 for 25 minutes. 90m, 1h, 1h30, and 1:30 also work. You can also click 5, 15, 25, 45, or 60 min. "
                + "The line under the field shows the length and when the timer ends.",
            "In the Notes window, Return on a new task asks \"How long?\" the same way. The ▶ button on a task starts "
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

    private static var popover: HelpSection {
        HelpSection(title: "The popover", paragraphs: [
            "Click the menu bar item, or press \(togglePopoverKeys), to open the popover.",
            "It shows the task, its note (Open ↗ opens the note), the time left, a progress bar, the start and end "
                + "times, the estimate, and the date.",
            "+1m, +5m, and +10m add time. +custom adds the minutes that you type.",
            "Pause stops the clock, and Resume starts it again. Stop ends the timer and keeps the task open. Done ends "
                + "the timer and checks the task.",
            "While the popover is open and a timer is active, single keys work too. They are in the table below.",
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
