# TT-12: Help tab in Settings

<!-- Last edited: 2026-09-29 10:10 PT -->

**TLDR:** We add a third tab, "Help", to the Settings window.
It explains every feature of the app in short sections, and it shows a table of every keyboard shortcut.
The shortcut table reads from `ShortcutCatalog`, the one list the key handlers also use, so the Help text can never disagree with what the keys really do.

## Where to find it

Click the `⏱` item in the macOS menu bar, then click "Settings…" in the popover footer, or press ⌘, while TickTick is active.
The Settings window opens with toolbar tabs: General, Shortcuts, and (after this issue) Help.
Click the Help tab to read the feature sections and the shortcut table.

## Orientation

The repo is `JacquesAttinger/TickTick`, the menu-bar timeboxing app described in `docs/planning.md`.
The Settings area lives in `TickTick/Settings/` and was built by TT-11 (merged to `master`).
`SettingsWindowController.swift` owns the one AppKit Settings window: an `NSTabViewController` with toolbar tabs, one `NSHostingController` per tab.
The `SettingsTab` enum in that file lists the tabs (`general`, `shortcuts`) and carries a comment that TT-12 adds Help.
`ShortcutCatalog.swift` is the single source of truth for every shortcut: `ShortcutInfo` (id, keys, description, scope) plus `ShortcutCatalog.all`, which returns every entry in the order global, popover, notes.
`ShortcutInfo.keysText` renders the current keys: for a recordable hotkey it reads `KeyboardShortcuts.getShortcut(for:)` live, so a rebound hotkey shows its new keys.
`ShortcutsSettingsView.swift` already shows parts of the catalog (the two hotkeys and the popover-key grid) and is the style to copy.
`TickTickTests/ShortcutCatalogTests.swift` already asserts that every catalog entry has a non-empty description and non-empty keys.

## What is wrong and why

Nothing is broken; this is a planned gap.
The `SettingsTab` enum has no `help` case, so the window has no Help tab, and no view explains the features.
The shape of the work:

1. `HelpContent.swift` (new) holds the Help text as data: seven feature sections (Create a task, Time a task, The menu bar, The popover, When time is up, Notes, Settings), each a title plus short plain-language paragraphs, and the shortcut groups computed from `ShortcutCatalog.all` grouped by scope.
2. `HelpView.swift` (new) renders that content as a grouped `Form`: one `Section` per feature section, then one `Section` per shortcut scope with a keys/description grid like the one in `ShortcutsSettingsView`.
3. `SettingsTab` gets a `help` case (title "Help", symbol `questionmark.circle`), and `makeView(for:)` returns the new view.
4. Because the content is data, a test can assert the acceptance criteria without rendering SwiftUI: every catalog entry appears in the Help shortcut groups, every scope has a group, and every feature section has text.

Two layout facts drive the view code.
First, the General and Shortcuts tabs disable scrolling and size the window to their content, but the Help text is long, so the Help tab keeps the form scrolling inside a fixed frame (width `SettingsWindowController.width`, height about 560 pt).
Second, `NSTabViewController` removes a deselected tab's view from the hierarchy, so `onAppear` fires each time you switch to Help; a small `@State` refresh token bumped there makes the body re-read `keysText`, which is how a hotkey rebound on the Shortcuts tab shows its new keys on the Help tab.

## Likely touched files

- `TickTick/Settings/HelpContent.swift` — new; the Help text as data (feature sections) plus the shortcut groups computed from `ShortcutCatalog`, so tests cover the acceptance criteria.
- `TickTick/Settings/HelpView.swift` — new; the Help tab view that renders `HelpContent` as a grouped, scrolling form.
- `TickTick/Settings/SettingsWindowController.swift` — add the `help` case to `SettingsTab` and return `HelpView` from `makeView(for:)`.
- `TickTick/Settings/ShortcutCatalog.swift` — add a display title to `ShortcutScope` and a `grouped` helper that returns `[(scope, [ShortcutInfo])]` in catalog order.
- `TickTickTests/HelpContentTests.swift` — new; asserts full catalog coverage, a group per scope, and non-empty section text.
- `TickTickTests/ShortcutCatalogTests.swift` — extend `everyEntryHasADescription` to also assert the scope grouping is total (every entry lands in exactly one group).

## Plan

1. **Catalog grouping.** Add `ShortcutScope.title` ("Anywhere", "In the popover", "In the Notes window") and `ShortcutCatalog.grouped: [(ShortcutScope, [ShortcutInfo])]`, which groups `all` by scope and keeps the order global, popover, notes. Extend `ShortcutCatalogTests` to assert the grouping covers every entry exactly once and every scope has a non-empty title.
2. **Help content.** Add `HelpContent.swift`: a `HelpSection` type (title, paragraphs) and the seven sections written from the "Product decisions" table in `docs/planning.md`, in plain short sentences that use the UI's own words ("Done", "Stop", "Inbox", "How long?"). Add `HelpContentTests.swift`: the section titles are exactly the seven required names in order, every section has non-empty text, and the ids in `ShortcutCatalog.grouped` equal the ids in `ShortcutCatalog.all`.
3. **Help view and tab.** Add `HelpView.swift` (a grouped `Form` in a fixed 480×560 frame, scrolling on, with a keys/description `Grid` per scope and an `onAppear` refresh token), add `SettingsTab.help`, and wire `makeView(for:)`. Run `make test lint`.
4. **Verify on the installed app.** `make install`, open Settings → Help, read every section in light and dark mode, rebind ⌃⌥Space on the Shortcuts tab, switch to Help, and see the new keys. Quit the app and kill every started process.

## Decisions made alone

- **The brief has a `## Revision` section but no plan exists on this branch.** The first planning run failed before launch ("Workspace not trusted"), so there is no plan to revise; I wrote the plan fresh and recorded this in Revision 1 below.
- **The Help text lives in a data model (`HelpContent`), not inline in the view.** Reason: the acceptance criteria ("every catalog entry shows", "every entry has a description and a scope") become plain unit tests instead of UI checks.
- **A rebound hotkey updates through body re-evaluation on `onAppear`.** The KeyboardShortcuts package's change notification (`shortcutByNameDidChange`) is internal to the package, so observing it would mean hard-coding its raw string. Rebinding can only happen on the Shortcuts tab, and `NSTabViewController` fires `onAppear` on every switch to Help, so an `onAppear` refresh is enough and is not fragile.
- **The Help tab scrolls inside a fixed height (about 560 pt); the other tabs do not scroll.** Reason: the Help text is much taller than the screen allows, and a Mac Settings window with a very tall fixed window would clip. The exact height is tuned by eye during step 3.
- **Scope display titles are "Anywhere", "In the popover", "In the Notes window".** Reason: plain words that match how the Shortcuts tab already describes them ("They work while the popover is open…"), instead of the internal names global/popover/notes.
- **Section order is the seven feature sections first, then the shortcut groups.** The issue lists the sections in that order, and shortcuts read best as a reference at the end.
- **The "Settings" Help section describes the toggles, the recorders, and Launch at login in one short section.** The issue names "Settings" as one section, so it does not get one subsection per toggle.
- **"Every feature in Product decisions shows" is proven by a manual mapping, not a text-matching test.** A test that greps the Help text for decision keywords would be brittle; the Verification section maps each decision row to its Help section instead.

## Out of scope found

- **No shortcut opens the Notes window** — every window but Notes has a keyboard path (⌘, for Settings, ⌃⌥T for the popover, ⌃⌥Space for quick add); a global or popover shortcut for Notes would fit `ShortcutCatalog`. Filed as a follow-up later; not fixed here.

## Verification

- `make test lint` — all tests pass, lint is clean, including the new `HelpContentTests` and the extended `ShortcutCatalogTests`.
- `make install`, then open the app from `/Applications`.
- Menu bar `⏱` → "Settings…" → Help tab: the tab shows with a `questionmark.circle` icon and the window title reads "Help".
- Read every section against the "Product decisions" table in `docs/planning.md`: Create a task (decisions 6, 7, 15 quick add), Time a task (8, 17), The menu bar (4, 9, 12), The popover (10, 15 popover keys), When time is up (11, 12, 18), Notes (5, 14, and the Inbox default), Settings (15b, launch at login).
- The shortcut table shows every entry: 2 global, 6 popover, 7 notes, grouped under "Anywhere", "In the popover", "In the Notes window".
- On the Shortcuts tab, rebind "Quick add" to new keys, switch to the Help tab: the table shows the new keys. Rebind it back.
- Switch macOS to dark mode (System Settings → Appearance): the Help tab stays readable, no fixed colors.
- Quit TickTick and confirm no started process is left.

## Revision 1

**Human comment:** none.
The brief's Revision section exists only because the first planning run failed before launch ("claude --bg exited 1: Workspace not trusted"), so no plan file existed on this branch.
**What changed:** this file is the first and complete plan, written fresh.
**Sections updated:** all sections were written new.
