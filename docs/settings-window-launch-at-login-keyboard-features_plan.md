# TT-11: Settings window, launch at login, keyboard features

<!-- Last edited: 2026-09-25 01:32 PT -->

**TLDR:** We give the app a Settings window and finish the keyboard features.
You get a "Launch at login" switch, a switch and a key recorder for each global hotkey, quick keys inside the popover (Space to pause, D for done, S for stop, 1 / 5 / 0 to add minutes), and a new global hotkey ⌃⌥T that opens the popover from anywhere.
One shared list of shortcuts (`ShortcutCatalog`) feeds both the key handlers and the future Help tab, so the docs can never disagree with the code.

## Where to find it

Click the `⏱` item in the macOS menu bar, then click "Settings…" in the popover (present in both the idle and the active state), or press ⌘, while TickTick is active.
The Settings window has a General tab (Launch at login) and a Shortcuts tab (toggles and recorders).
The popover keys work while the popover is open with a timer active: Space pauses or resumes, D finishes, S stops, and 1 / 5 / 0 add 1 / 5 / 10 minutes.
⌃⌥T opens or closes the popover from any app, the same way ⌃⌥Space opens quick-add.

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, the TickTick menu-bar timeboxing app described in `docs/planning.md`.
TT-1 is on `master`. TT-2 through TT-9 are open PRs (#13 to #20), and this branch merges the TT-9 branch, which has all of them, so the step 0 gate is met.
The code on the branch is the source of truth. "As built" below lists where the code differs from this plan.
The planned folder layout gives this issue the `TickTick/Settings/` folder: `SettingsView.swift`, `GeneralSettingsView.swift`, `ShortcutsSettingsView.swift`, and `ShortcutCatalog.swift` (`HelpView.swift` in the same folder belongs to TT-12).
Three merged pieces are the insertion points:
`TickTick/App/TickTickApp.swift` (from TT-1) already declares an empty SwiftUI `Settings { EmptyView() }` scene with a comment that TT-11 fills it in.
`TickTick/MenuBar/` (from TT-5) owns `StatusItemController` with the `toggle()` that a global hotkey needs, and `TimerPopoverView` with a disabled "Settings…" placeholder slot to make real.
`TickTick/QuickAdd/QuickAddController.swift` (from TT-7) declares `KeyboardShortcuts.Name.quickAdd`, which its own plan says moves into `ShortcutCatalog` in this issue.
`project.yml` (from TT-1) already declares the `KeyboardShortcuts` SPM package, and `SMAppService` is an Apple framework, so no project change is needed.
Product decision 15 defines the system extras and the popover keys, and decision 15b defines the Settings window that switches each of them.

## What is wrong and why

Nothing is broken; this is the first M3 gap.
After TT-5 and TT-7 merge, the timer is fully usable, but every system extra is always on, nothing can be rebound, the popover is mouse-only, and the empty Settings scene shows a blank window.
The shape of the work:

1. A `Preferences` object (`@Observable`, backed by `UserDefaults`) holds the three on/off switches: quick-add hotkey, open-popover hotkey, popover keys.
2. `ShortcutCatalog` is the single source of truth for every shortcut: id, keys, description, and scope (`global` / `popover` / `notes`), plus the `KeyboardShortcuts.Name` constants for the two recordable global hotkeys.
3. A local key monitor, active only while the popover is open, maps Space / D / S / 1 / 5 / 0 to `TimerEngine` calls through a pure, testable mapping function, and stands down while a text field is being edited.
4. `KeyboardShortcuts.Name.togglePopover` (default ⌃⌥T) calls the same `StatusItemController.toggle()` a click uses.
5. The Settings scene gets a real `SettingsView` with a General tab (`SMAppService.mainApp` launch-at-login toggle that shows the real registration status) and a Shortcuts tab (recorders and toggles), and the popover's "Settings…" placeholder becomes a working button.
6. Every toggle takes effect at once: hotkey toggles call `KeyboardShortcuts.enable` / `.disable`, and the popover key monitor checks the preference live.

## As built

- **The Settings window is AppKit, not the SwiftUI `Settings` scene.** The popover lives outside every SwiftUI scene, so it cannot open that scene (TT-8 chose AppKit for the Notes window for the same reason). `SettingsWindowController` (`TickTick/Settings/SettingsWindowController.swift`) shows an `NSTabViewController` with toolbar tabs, the standard look of a Mac Settings window. The empty `Settings` scene stays, and `TickTickApp` replaces its "Settings…" menu item (⌘,) with one that opens the AppKit window. So there is no `SettingsView.swift`; the tabs are the `SettingsTab` enum, and TT-12 adds `.help` there.
- **Dock icon while Settings is open:** the window uses `ActivationPolicyController.windowWillShow(_:)`, like the Notes window, so it gets a Dock icon, Cmd-Tab, the main menu (⌘W), and the keyboard goes back to the previous app when it closes.
- **`GlobalHotkeys`** (`TickTick/Settings/GlobalHotkeys.swift`) follows `Preferences` with Observation and calls `KeyboardShortcuts.enable` / `.disable`. It also registers ⌃⌥T. `AppDelegate` only builds it. `QuickAddController.registerHotkey()` still registers ⌃⌥Space.
- **`LaunchAtLoginModel`** (`TickTick/Settings/LaunchAtLoginModel.swift`) wraps `SMAppService.mainApp` behind a small `LoginItemService` protocol, so tests use a fake. The switch is on for `.enabled` and also for `.requiresApproval` (with the approval hint), so you can turn a waiting item off again.
- **Popover keys:** `PopoverKeyCommand` (in `PopoverKeyHandler.swift`) is the one list of the six keys. `ShortcutCatalog.popoverKeys` and `PopoverKeyMonitor` both read it. Held keys repeat with no action and no beep. Space in overtime beeps, like the dimmed Pause button. Keys with ⌘, ⌃, or ⌥ pass through.
- **⌃⌥T activates TickTick before the popover shows** (`ActivationPolicyController.activateForHotkey()`), so the popover keys work after the hotkey too. A click still uses `activateForClick(_:)`.
- **Notes-scope entries:** TT-8 and TT-9 are on the branch, so the catalog has ⌘N, Return, Esc, ⌘↩, ⇧⌘C, ↑ / ↓, and ⌫. `NoteSidebarView` and `TaskRowView` now read ⌘N, ⌘↩, and ⇧⌘C (and their tooltips) from the catalog.
- **The idle popover hint** ("New task: ⌃⌥Space") shows the recorded keys, and it hides while the quick-add hotkey is off.
- **Window size and title:** each tab has its own height (General is short, Shortcuts is tall), and the window grows or shrinks down from a fixed top edge when you change tabs, like other Mac Settings windows.
  The window title is the name of the selected tab.
- **Popover keys section:** the switch is named "Single keys", because the section title already says "Popover keys".

## Likely touched files

- `TickTick/Settings/ShortcutCatalog.swift` — new; the `ShortcutInfo` type (id, keys, description, scope), the full catalog list, and the `KeyboardShortcuts.Name` constants (`quickAdd` moves here, `togglePopover` is born here).
- `TickTick/Settings/Preferences.swift` — new; `@Observable` on/off state for the three features, backed by an injectable `UserDefaults`.
- `TickTick/Settings/SettingsWindowController.swift` — new; the AppKit Settings window with toolbar tabs (`SettingsTab`), in place of the planned `SettingsView.swift`.
- `TickTick/Settings/GeneralSettingsView.swift` — new; the launch-at-login toggle.
- `TickTick/Settings/LaunchAtLoginModel.swift` — new; the `SMAppService` status model behind that toggle.
- `TickTick/Settings/GlobalHotkeys.swift` — new; turns the two hotkeys on and off to match `Preferences`, and registers ⌃⌥T.
- `TickTick/Settings/ShortcutsSettingsView.swift` — new; `KeyboardShortcuts.Recorder` rows and the three enable toggles.
- `TickTick/MenuBar/PopoverKeyHandler.swift` — new; the pure key-to-command mapping and the local `NSEvent` monitor lifecycle.
- `TickTick/MenuBar/StatusItemController.swift` — edited; installs and removes the popover key monitor with the popover, and exposes `toggle()` to the global hotkey.
- `TickTick/MenuBar/TimerPopoverView.swift` — edited; the disabled "Settings…" placeholder becomes a real button in the idle and the active state.
- `TickTick/QuickAdd/QuickAddController.swift` — edited; its local `KeyboardShortcuts.Name.quickAdd` declaration is removed in favor of the catalog's.
- `TickTick/App/TickTickApp.swift` — edited; the "Settings…" menu item (⌘,) opens the AppKit Settings window.
- `TickTick/App/ActivationPolicyController.swift` — edited; `activateForHotkey()` for ⌃⌥T.
- `TickTick/Notes/NoteSidebarView.swift` and `TickTick/Notes/TaskRowView.swift` — edited; read ⌘N, ⌘↩, and ⇧⌘C from the catalog.
- `TickTick/App/AppDelegate.swift` — edited; builds the shared `Preferences`, registers the ⌃⌥T handler, and applies the stored enable state at launch (kept to a few lines; this file is a known merge hotspot).
- `TickTickTests/ShortcutCatalogTests.swift` — new; catalog completeness and uniqueness.
- `TickTickTests/PopoverKeyHandlerTests.swift` — new; the pure key mapping under every state.
- `TickTickTests/PreferencesTests.swift` — new; defaults and persistence round-trip, and `GlobalHotkeys` following the switches.
- `TickTickTests/LaunchAtLoginModelTests.swift` — new; on, off, errors, and approval with a fake login item.
- `docs/settings-window-launch-at-login-keyboard-features_plan.md` — this plan.

## Plan

0. **Sync the branch.**
   Run `git fetch` and merge `origin/master` into this branch.
   Confirm the TT-5 and TT-7 code is present (`TickTick/MenuBar/StatusItemController.swift`, `TickTick/MenuBar/TimerPopoverView.swift`, `TickTick/QuickAdd/QuickAddController.swift`) and that `make gen build test lint` passes before any new code.
   If either dependency has not merged, stop and report the unmet dependency instead of coding against a guessed API.
   If the merged APIs differ from the shapes assumed here (names, the popover placeholder shape, where `.quickAdd` lives), adapt to the real APIs and note the deltas in the PR description.
1. **Preferences and catalog commit.**
   Add `TickTick/Settings/Preferences.swift`: an `@Observable @MainActor` final class with three `Bool` properties — `quickAddHotkeyEnabled`, `togglePopoverHotkeyEnabled`, `popoverKeysEnabled` — each defaulting to `true`, read from and written through an injected `UserDefaults` (default `.standard`) so tests can use a scratch suite.
   Add `TickTick/Settings/ShortcutCatalog.swift`:
   - `extension KeyboardShortcuts.Name` with `quickAdd` (default ⌃⌥Space, moved verbatim from `QuickAddController`) and `togglePopover` (default ⌃⌥T).
   - `struct ShortcutInfo: Identifiable` with `id` (a stable string), `keys` (a display string, or the live binding of a `KeyboardShortcuts.Name` for the two recordable entries), `description`, and `scope` (`enum ShortcutScope { global, popover, notes }`).
   - `enum ShortcutCatalog` with `static let all: [ShortcutInfo]` covering: the two global hotkeys, the six popover keys (Space, D, S, 1, 5, 0), and the notes-scope shortcuts that exist in the merged code at implementation time (see decisions).
   Remove the `.quickAdd` declaration from `TickTick/QuickAdd/QuickAddController.swift`.
   Add `TickTickTests/PreferencesTests.swift` (defaults are true, a write round-trips through the injected suite) and `TickTickTests/ShortcutCatalogTests.swift` (ids are unique, every entry has a non-empty description, the six popover keys and both global ids are present).
2. **Popover keys commit.**
   Add `TickTick/MenuBar/PopoverKeyHandler.swift`:
   - A pure `static func command(for key: String) -> PopoverKeyCommand?` mapping `" "` → pause/resume, `"d"` → done, `"s"` → stop, `"1"` / `"5"` / `"0"` → extend by 60 / 300 / 600 seconds, else `nil`, driven by the same key strings the catalog entries carry so the two cannot drift.
   - A monitor object that installs an `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` and removes it on deinit or `stop()`.
   - The monitor swallows and executes a mapped key only when `preferences.popoverKeysEnabled` is true, the engine is in an active state (running / paused / overtime), and no text input is first responder (the "+custom" field must keep receiving digits and Space); every other event passes through untouched.
   Edit `TickTick/MenuBar/StatusItemController.swift`: start the monitor when the popover shows and stop it when the popover closes, so the keys exist only "while the popover is open" as decision 15 says.
   Add `TickTickTests/PopoverKeyHandlerTests.swift`: one case per key, an unmapped key returns `nil`, and case-insensitivity for D and S.
3. **Global toggle-popover hotkey commit.**
   Edit `TickTick/App/AppDelegate.swift`: register `KeyboardShortcuts.onKeyUp(for: .togglePopover)` to call `StatusItemController.toggle()`, build the shared `Preferences`, and on launch call `KeyboardShortcuts.enable` / `.disable` for `.quickAdd` and `.togglePopover` from the stored preference values.
   Wire preference changes (via Observation) so flipping either hotkey toggle calls `KeyboardShortcuts.enable` / `.disable` at once — a disabled hotkey must stop swallowing the key combination system-wide, not just ignore it.
4. **Settings window commit.**
   Add `TickTick/Settings/SettingsView.swift`: a `TabView` with the General and Shortcuts tabs (system-symbol tab icons), a fixed reasonable width, and the shared `Preferences` passed in; TT-12 adds its Help tab beside these.
   Add `TickTick/Settings/GeneralSettingsView.swift`: a "Launch at login" `Toggle` bound to a small model over `SMAppService.mainApp` — the toggle state reads `status == .enabled`, turning it on calls `register()`, turning it off calls `unregister()`, a thrown error reverts the toggle and shows the error text inline, `.requiresApproval` shows a hint with a button that opens the Login Items pane, and the status is re-read each time the window becomes key (it can change behind our back in System Settings).
   Add `TickTick/Settings/ShortcutsSettingsView.swift`: a "Quick add" row and an "Open popover" row, each an enable `Toggle` plus a `KeyboardShortcuts.Recorder` for its name (the recorder is disabled while its toggle is off), and a "Popover keys" section with one enable `Toggle` and a caption listing the six keys from `ShortcutCatalog`.
   Edit `TickTick/App/TickTickApp.swift`: the `Settings` scene body becomes `SettingsView` with the shared `Preferences` (reached through the `AppDelegate` adaptor).
   Edit `TickTick/MenuBar/TimerPopoverView.swift`: the "Settings…" placeholder becomes a real button in the idle and the active state; it activates the app, opens the Settings scene through `openSettings`, and closes the popover.
5. **Manual verification and polish commit.**
   Run the full Verification list below on the installed app and fix what looks wrong: tab sizing, toggle alignment, recorder focus, dark-mode contrast, popover key edge cases.
   Finishing pass: every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file over 500 lines, no function over 75 lines, `make test lint` green, push, and open the PR linked to TOD-13.

## Decisions made alone

- **Blocked-dependency handling:** TT-5 and TT-7 are unmerged plan-stage branches, so step 0 makes "merge a master that contains both" a hard precondition and hard-stops otherwise — the same call every sibling plan made, because coding against guessed APIs produces an unbuildable branch.
- **Popover keys use a local `NSEvent` key-down monitor owned by the popover lifecycle,** not per-view `.keyboardShortcut` modifiers.
  Reason: the keys must work no matter which control has focus inside the popover, and a single monitor with one mapping function is testable and lives exactly as long as the popover, which is the scope decision 15 defines.
- **Popover keys stand down while any text input is first responder.**
  Reason: the "+custom" field from TT-5 needs Space and the digits 1 / 5 / 0 as ordinary typing; a shortcut that steals characters from a visible text field would be a bug, and the issue does not address the conflict.
- **Popover keys act only in an active timer state (running / paused / overtime) and do nothing in the idle popover.**
  Reason: pause, done, stop, and extend have no meaning without a timer, and the acceptance criterion "does nothing when popover keys are off" implies silent no-ops are the correct off-path behavior.
- **Turning a global hotkey off calls `KeyboardShortcuts.disable`,** rather than keeping the handler registered and ignoring the event.
  Reason: a registered hotkey swallows the key combination system-wide, so "off" must give ⌃⌥Space or ⌃⌥T back to other apps; the library's enable/disable exists for exactly this and takes effect at once.
- **Popover keys are fixed and not recordable; only the two global hotkeys get recorders.**
  Reason: the issue's Shortcuts-tab scope lists recorders for quick-add and open-popover and only an on/off toggle for popover keys.
- **`Preferences` is a small `@Observable` class over an injected `UserDefaults`,** not scattered `@AppStorage` properties.
  Reason: the handlers (AppKit side) and the Settings views (SwiftUI side) must read the same live values for "takes effect at once, no relaunch", and an injected suite makes the persistence testable; `@AppStorage` is view-only.
- **The two `KeyboardShortcuts.Name` constants live in `ShortcutCatalog.swift`.**
  Reason: the issue names the catalog as the single home for shortcut definitions, and TT-7's plan explicitly parked `.quickAdd` in its controller "until TT-11", so this move is the anticipated one.
- **Catalog entries for the recordable hotkeys carry their `KeyboardShortcuts.Name` and render the live binding as their key text,** while popover and notes entries carry fixed display strings.
  Reason: a rebound hotkey must show its new keys in the future Help tab without a second source of truth — drift-proofing is the catalog's whole point.
- **Notes-scope shortcuts enter the catalog only if their features exist in the merged master at implementation time.**
  Reason: the catalog's scope enum must include `notes` per the issue, but documenting unmerged M2 behavior (TT-8 / TT-9 row keys) would drift if those plans change; TT-12's acceptance test ("every catalog entry has a description") keeps the catalog honest either way, and missing entries are a one-line follow-up when M2 merges.
- **⌘, works whenever TickTick is active, and the popover "Settings…" button is the primary path.**
  Reason: the SwiftUI `Settings` scene provides the ⌘, binding through the app menu, but an `LSUIElement` accessory app has no visible menu bar until it is activated, so the button activates the app explicitly (`NSApp.activate`) before opening the window; this matches how the issue pairs the two paths.
- **The launch-at-login toggle reflects `SMAppService.mainApp.status` and re-reads it when the window becomes key.**
  Reason: the issue demands "shows the real registration status", and the user can flip the same switch in System Settings → Login Items while our window is open.
- **Registration errors revert the toggle and show the error inline; `.requiresApproval` gets a hint plus a button to the Login Items pane.**
  Reason: the issue does not cover the failure paths, and a toggle that silently shows a state the system rejected would violate "shows the real registration status".
- **Extend amounts are 60 / 300 / 600 seconds hard-wired next to the key mapping.**
  Reason: decision 15 fixes 1 / 5 / 0 to +1 / +5 / +10 min; no configurability is asked for.
- **Two extra files beyond the planned four (`Preferences.swift`, `PopoverKeyHandler.swift`).**
  Reason: sources are globbed so new files cost nothing, the 500-line limit punishes folding them into `ShortcutCatalog.swift` or `StatusItemController.swift`, and both siblings made the same split for pure-logic testability.
- **`AppDelegate` edits stay minimal (build `Preferences`, register ⌃⌥T, apply stored enable state).**
  Reason: TT-7's plan flags `AppDelegate.swift` as a three-way merge hotspot; the popover-key wiring therefore lives in `StatusItemController`, not the delegate.

## Out of scope found

- **Help tab** — the third Settings tab that renders `ShortcutCatalog`; TT-12 (TOD-15) owns it, and this issue only guarantees the catalog data it needs.
- **Notes-scope catalog entries for M2 features** — if TT-8 / TT-9 have not merged when this issue implements, their shortcuts (⌘N, row navigation) join the catalog in a follow-up or in TT-12.
- **Hotkey conflict warnings** — recording a combination another app or the system already uses gets no custom warning beyond what the `KeyboardShortcuts` recorder does itself; nothing in the decisions asks for more.
- **A "restore default shortcut" button** — the recorder allows clearing and rebinding, but no explicit reset-to-⌃⌥Space affordance is specified; possible TT-13 polish.
- **AppDelegate merge hotspot** — TT-4, TT-5, TT-7, and this issue all touch `TickTick/App/AppDelegate.swift`; a composition-root refactor still belongs to no current issue (first flagged by TT-7's plan).

## Verification

Run in the worktree after the step 0 merge:

- `make gen test lint` — exits 0; the new `PreferencesTests`, `ShortcutCatalogTests`, and `PopoverKeyHandlerTests` suites run and pass.
- The test list must include, by name: catalog ids are unique, every catalog entry has a description, both global ids and all six popover keys are present, each popover key maps to its command, an unmapped key returns nil, preference defaults are true, and a preference write round-trips.
- `git diff origin/jacques/tod-14-tt-9-task-rows-and-the-confirm-flow-code --stat` — only files under `TickTick/Settings/`, `TickTick/MenuBar/`, `TickTick/QuickAdd/` (the moved name only), `TickTick/App/`, `TickTick/Notes/` (the catalog keys only), `TickTickTests/`, and `docs/` change.

Manual check on the installed app (`make install`):

1. Start a timer (⌃⌥Space flow), open the popover, and press Space (pauses), Space (resumes), 1 / 5 / 0 (the remaining time grows by 1 / 5 / 10 min), S (stops); start another timer and press D (timer ends and the task is checked in Inbox).
2. With the "+custom" field focused, type `10` and press Space: the characters land in the field and no timer command fires.
3. Open Settings → Shortcuts, turn "Popover keys" off: every key from step 1 now does nothing, with no relaunch; turn it back on and Space works again.
4. From another app press ⌃⌥T: the popover opens; ⌃⌥T again closes it. Turn "Open popover" off: ⌃⌥T does nothing and the combination reaches the frontmost app again; back on, it works at once.
5. Rebind quick-add to a new combination in the recorder: the new keys open the panel at once and ⌃⌥Space does nothing; rebind back.
6. Click "Settings…" in the idle popover and in the active popover: the window opens and comes to the front both times; ⌘, opens it while the Settings or Notes window is active.
7. General → turn "Launch at login" on: TickTick appears under System Settings → General → Login Items; turn it off there and re-focus our window: the toggle updates to off.
8. With launch-at-login on, log out and log back in: TickTick is running and shows `⏱` (this step needs Jacques's session; note it in the PR if not run).
9. Check both tabs and the popover in light mode and dark mode: no clipped text, correct contrast.
10. Quit TickTick via the popover, then `pgrep -x TickTick` to confirm nothing is left running.
