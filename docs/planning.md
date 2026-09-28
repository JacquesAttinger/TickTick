# TickTick — planning

## TLDR

TickTick is a Mac app for one person.
You write a task, you say how long it will take, and a countdown starts in the menu bar at the top of the screen.
When time is up, the screen flashes, a sound plays, and a notification appears.
The app also has a notes window where each note is a list of tasks with checkboxes.
We build it in 13 steps.
Each step is one Linear issue that one Claude agent can do in one pull request.

## Context

The repo `JacquesAttinger/TODO_TIMER` is empty (only `README.md`).
Jacques wants a timeboxing to-do app for his own Mac.
Today he uses the third-party "Menubar Countdown" app.
That app cannot show a task name, cannot flash the screen, and has no to-do list.
TickTick replaces it for daily use.
Menubar Countdown and the `menubar-timer` MCP server in `~/code/tools/menubar-timer-mcp` stay installed and do not change.

## Product decisions (from the grilling session)

| # | Topic | Decision |
|---|---|---|
| 1 | Audience | Only Jacques. Local build, signed with the existing "Apple Development" cert (team `UH88Q62C4G`), copied to `/Applications`. |
| 2 | Stack | Native Swift 6 + SwiftUI, with AppKit where SwiftUI is not enough (status item, popover, flash windows, quick-add panel). |
| 3 | App split | One integrated app. Timer and notes share one data store. |
| 4 | Presence | Hybrid. Always in the menu bar. Dock icon and Cmd-Tab entry only while the Notes window is open. |
| 5 | Note model | A note has a title and an ordered list of task rows with checkboxes. No free text. |
| 6 | Confirm flow | Return on a new task opens an inline "How long?" field. Return starts the timer. Esc skips (task saved, no timer). Every row has a ▶ button to start a timer later. |
| 7 | Duration input | Free text: `25` = 25 min, `90m`, `1h`, `1h30`, `1:30`. Chips: 5 / 15 / 25 / 45 / 60 min. Live preview: `= 1 h 30 min · ends 3:42 PM`. |
| 8 | Concurrency | One active timer. Starting a second one asks: "Stop "A" (12 min left) and start "B"?" |
| 9 | Menu bar text | Running: `⏱ Write cover letter · 24:13` (name cut to 24 characters + "…"). Paused: `⏸ Write cover letter · 24:13` (dimmed). Idle: `⏱` only. |
| 10 | Popover | Task name, note name + Open ↗, time left, progress bar, started / ends, estimate, date. Buttons: +1m, +5m, +10m, +custom, Pause/Resume, Stop (timer only), Done (stop + check the task). |
| 11 | Alarm | White overlay flashes 3 times on every display in about 1.5 s. Clicks pass through. Sound plays once. Banner notification top right. If Reduce Motion is on: one slow fade instead of 3 flashes. |
| 12 | After zero | Menu bar turns red and counts up (`+2:13`) until Done, +5 min, or Stop. The notification has the same 3 buttons. |
| 13 | Storage | SwiftData, local only. Models stay CloudKit-compatible so iCloud sync can come later. |
| 14 | Notes extras | Drag to reorder tasks. A checked task stays in its place with a filled checkbox, like an Apple Notes checklist (changed on 2026-09-28: no separate "Completed (n)" section). Per-row badge `⏱ 45m est · 52m actual`. |
| 15 | System extras | Launch at login. Global quick-add hotkey (default ⌃⌥Space, task goes to "Inbox" note). Popover keys: Space pause/resume, D done, S stop, 1 / 5 / 0 = +1 / +5 / +10 min. Global open-popover hotkey (default ⌃⌥T). |
| 15b | Settings | A Settings window with an on/off toggle for each item in row 15, hotkey recorders, and a Help tab that explains every feature and every shortcut. |
| 16 | Claude Code | No remote control (no URL scheme, no AppleScript). |
| 17 | Sleep / lock | The timer follows real clock time. If it expired while the Mac slept, the alarm fires on wake. An active timer survives app quit or crash. |
| 18 | Focus mode | Flash and sound always fire. The banner uses the Time Sensitive interruption level. |
| 19 | Name | TickTick. Bundle ID `com.jacquesattinger.TickTick`. (A commercial to-do app has the same name. It is not installed here, so this is fine for a personal build. Rename it if you ever share the app.) |
| 20 | Build order | Timer first (M1), then the Notes window (M2), then Settings and polish (M3). |

## Behavior defaults (not asked, change them if you disagree)

- **Inbox note:** created on first launch and always first in the sidebar. You can rename it, but you cannot delete it. Quick-add puts tasks here.
- **Actual time:** the sum of all timer sessions for a task. It counts running time and overtime, and it does not count paused time.
- **Check the box of the running task:** the same as Done.
- **Delete the running task:** stops the timer. The session is saved with outcome `deleted`.
- **Rename the running task:** the menu bar updates live.
- **Check or uncheck a task:** it stays in its place. A done task shows a filled checkbox and gets no ▶.
- **Alarm sound:** the system sound "Glass". It is not configurable in v1.
- **Notification permission:** requested on first launch. If you deny it, flash and sound still work, and the popover shows a hint.
- **Quit:** the popover always has "Quit TickTick", because the app often has no Dock icon.
- **Minimum macOS:** 26.0. No App Sandbox (personal build).

## Technical approach

- **Project:** XcodeGen `project.yml` generates the `.xcodeproj`, and the `.xcodeproj` is not committed.
  Reason: many agents work in parallel, and a hand-edited `project.pbxproj` gives merge conflicts all the time.
  Sources are included by folder glob, so adding a file never touches the project file.
- **Menu bar:** AppKit `NSStatusItem` + `NSPopover` hosting SwiftUI, not SwiftUI `MenuBarExtra`.
  Reason: `MenuBarExtra` has no public API to open its window from code (we need that for the ⌃⌥T hotkey), and it does not reliably show a red label (we need that for overtime).
- **Timer engine:** a pure state machine (`idle / running / paused / overtime`) with an injected `Clock`.
  It stores `endDate` (running) or `remaining` (paused), never a tick counter, so sleep and relaunch cannot make it drift.
  A 1 s UI refresh reads from it.
  `NSWorkspace.didWakeNotification` makes it check expiry again.
  The active timer is saved to `UserDefaults` on every change and restored on launch.
- **Notifications:** `UNUserNotificationCenter`, category `TIMER_DONE` with actions Done / +5 min / Stop.
  The notification is scheduled ahead with a time-interval trigger. It is rescheduled on pause, resume, and extend, and cancelled on stop and done.
  The entitlement is `com.apple.developer.usernotifications.time-sensitive`. If signing with the personal team rejects it, fall back to `.active` and write down the limit in the README.
- **Flash:** one borderless `NSWindow` for each `NSScreen`, at level `.screenSaver`, with `ignoresMouseEvents = true` and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
  It animates white alpha 0 → 0.6 → 0 three times (at most 2 flashes per second, which is below the photosensitivity limit of 3 per second).
  It reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
- **Sound:** `NSSound(named: "Glass")`. Focus mode does not silence it.
- **Hotkeys:** SPM package `sindresorhus/KeyboardShortcuts` (global hotkeys without Accessibility permission, plus a ready-made recorder view for Settings).
- **Launch at login:** `SMAppService.mainApp` (built in, no package).
- **Hybrid Dock:** `LSUIElement = YES` in Info.plist. `NSApp.setActivationPolicy(.regular)` when the Notes window opens, and `.accessory` when it closes.
- **SwiftData models (CloudKit-compatible):** every property is optional or has a default, no `@Attribute(.unique)`, and all relationships are optional with explicit inverses.
  - `Note`: id, title, createdAt, sortIndex, isInbox, tasks.
  - `TaskItem`: id, title, isDone, completedAt, sortIndex, estimateSeconds?, note, sessions.
  - `TimerSession`: id, task, startedAt, endedAt?, plannedSeconds, activeSeconds, outcome (`done / stopped / replaced / deleted`).
- **Tests:** Swift Testing (`import Testing`) for all pure logic: duration parser, formatters, timer engine (fake clock), task ordering and completion rules. UI is checked by hand in each issue's Verify section.

### Folder layout

```
project.yml  Makefile  .swiftlint.yml  .swiftformat  .githooks/pre-commit  scripts/setup.sh
TickTick/
  App/        TickTickApp.swift, AppDelegate.swift, ActivationPolicyController.swift
  Model/      Note.swift, TaskItem.swift, TimerSession.swift, ModelStore.swift, TaskService.swift
  Time/       DurationParser.swift, TimeFormatting.swift
  Timer/      Clock.swift, TimerState.swift, TimerEngine.swift, ActiveTimerStore.swift
  MenuBar/    StatusItemController.swift, TimerPopoverView.swift
  Alarm/      FlashController.swift, AlarmSound.swift, NotificationController.swift
  QuickAdd/   QuickAddPanel.swift, QuickAddView.swift, DurationPromptView.swift
  Notes/      NotesWindow.swift, NoteSidebarView.swift, NoteDetailView.swift, TaskRowView.swift, TaskReorder.swift, TaskTimeBadge.swift
  Settings/   SettingsView.swift, GeneralSettingsView.swift, ShortcutsSettingsView.swift, HelpView.swift, ShortcutCatalog.swift
  Resources/  Assets.xcassets, Info.plist, TickTick.entitlements
TickTickTests/
```

## Rules for every issue

- Start from a fresh pull of `master`, work in a git worktree, and open one PR for each issue. Link the PR to the Linear issue. Do not merge it.
- Every Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`.
- No file over 500 lines. No function over 75 lines. SwiftLint enforces both.
- The pre-commit hook (SwiftFormat + SwiftLint) must pass. Never use `--no-verify`.
- `make test` passes. New pure logic gets tests.
- Do the issue's Verify steps on the real app (`make install`, then open TickTick) and look closely at the UI. Fix anything that looks wrong.
- Before you report done, quit TickTick and kill every process you started.

## Steps (one Linear issue each)

Dependency graph:

```
TT-1 ─┬─ TT-2 ─┬─ TT-4 ─┬─ TT-5 ─┐
      └─ TT-3 ─┘        ├─ TT-6  ├─ TT-11 ── TT-12 ── TT-13
                        └─ TT-7 ─┤
               TT-2 ── TT-8 ─────┴─ TT-9 ── TT-10
```

TT-2 and TT-3 can run in parallel.
TT-5, TT-6, and TT-7 can run in parallel.
TT-8 only needs TT-2, so it can start early if you want.

Linear: team Todo_Timer, project [TODO_TIMER](https://linear.app/todo-timer/project/todo-timer-9aaae128bdbf), milestones M1 / M2 / M3.
Each issue has "blocked by" relations that match the graph above.

| Step | Linear | Milestone |
|---|---|---|
| TT-1 | [TOD-5](https://linear.app/todo-timer/issue/TOD-5) | M1 |
| TT-2 | [TOD-6](https://linear.app/todo-timer/issue/TOD-6) | M1 |
| TT-3 | [TOD-7](https://linear.app/todo-timer/issue/TOD-7) | M1 |
| TT-4 | [TOD-8](https://linear.app/todo-timer/issue/TOD-8) | M1 |
| TT-5 | [TOD-9](https://linear.app/todo-timer/issue/TOD-9) | M1 |
| TT-6 | [TOD-10](https://linear.app/todo-timer/issue/TOD-10) | M1 |
| TT-7 | [TOD-11](https://linear.app/todo-timer/issue/TOD-11) | M1 |
| TT-8 | [TOD-12](https://linear.app/todo-timer/issue/TOD-12) | M2 |
| TT-9 | [TOD-14](https://linear.app/todo-timer/issue/TOD-14) | M2 |
| TT-10 | [TOD-16](https://linear.app/todo-timer/issue/TOD-16) | M2 |
| TT-11 | [TOD-13](https://linear.app/todo-timer/issue/TOD-13) | M3 |
| TT-12 | [TOD-15](https://linear.app/todo-timer/issue/TOD-15) | M3 |
| TT-13 | [TOD-17](https://linear.app/todo-timer/issue/TOD-17) | M3 |

---

### M1 — Timer core (usable at the end of M1)

#### TT-1 · Project scaffold, tooling, and lint hook (TOD-5)

- **Goal:** an empty TickTick app that builds, runs, and shows `⏱` in the menu bar.
- **Prerequisite (Jacques runs by hand):** `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` (xcodebuild fails with the current CommandLineTools path).
- **Scope:**
  - `scripts/setup.sh`: `brew install xcodegen swiftlint swiftformat`, then `git config core.hooksPath .githooks`.
  - `project.yml`: app target `TickTick` (macOS 26.0, Swift 6, strict concurrency), test target `TickTickTests`, team `UH88Q62C4G`, automatic signing, SPM dependency `KeyboardShortcuts`.
  - `Info.plist` with `LSUIElement = YES`. `TickTick.entitlements` with the time-sensitive notification key.
  - `Makefile`: `gen`, `build`, `test`, `lint`, `format`, `install` (build Release, copy to `/Applications`, relaunch).
  - `.swiftlint.yml` (`file_length` error 500, `function_body_length` error 75), `.swiftformat`, `.githooks/pre-commit`.
  - `.gitignore` (the generated `.xcodeproj`, `build/`, `DerivedData`, `.DS_Store`).
  - `AppDelegate` creates an `NSStatusItem` with `⏱` and a menu with "Quit TickTick".
  - A short `README.md`: setup, `make` targets.
- **Acceptance:** `scripts/setup.sh && make gen build test lint` succeeds on a clean clone. `make install` shows `⏱` in the menu bar, with no Dock icon. A commit with a lint violation is blocked.

#### TT-2 · SwiftData model and task service (TOD-6)

- **Depends on:** TT-1.
- **Scope:** `Note`, `TaskItem`, `TimerSession` as described in Technical approach. `ModelStore` builds the container and creates the Inbox note on first launch. `TaskService` has these operations: create note, rename note, delete note (refuses Inbox), create task at index, rename task, delete task, toggle done (sets `completedAt`), move task (rewrites `sortIndex`), open and completed task lists in order, and `actualSeconds(for:)`.
- **Acceptance:** unit tests with an in-memory container cover every operation, including "Inbox cannot be deleted" and "uncheck returns the task to its old position". No UI.

#### TT-3 · Duration parser and time formatting (TOD-7)

- **Depends on:** TT-1. Can run in parallel with TT-2.
- **Scope:** `DurationParser.parse(_:) -> TimeInterval?` for `25`, `25m`, `90 min`, `1h`, `1h30`, `1h 30m`, `1:30`, `1.5h`, with whitespace and case tolerance. Reject 0, negatives, and values over 24 h. `TimeFormatting`: countdown `24:13` / `1:02:03`, overtime `+2:13`, human `1 h 30 min`, clock `3:42 PM` (locale-aware), and "ends at" preview text.
- **Acceptance:** table-driven tests for valid inputs, invalid inputs, and edge cases (for example `0`, `abc`, `25h`, `:30`).

#### TT-4 · Timer engine (TOD-8)

- **Depends on:** TT-2, TT-3.
- **Scope:** `Clock` protocol (system clock + test clock). `TimerEngine` (`@Observable`, `@MainActor`) with states idle / running / paused / overtime, and the operations `start(task:seconds:)`, `pause`, `resume`, `extend(seconds:)`, `stop`, `done`. A switch rule: `start` while active returns `.needsConfirmation(current:)`, and `start(…, replacing: true)` ends the old session as `replaced`. It creates and closes `TimerSession` records through `TaskService`, and `done` checks the task. It emits an `expired` event once, when it enters overtime. `ActiveTimerStore` saves the state to `UserDefaults` and restores it on launch (it goes straight to overtime if the end passed while quit). It checks again on `didWakeNotification`. `TaskService` hooks: delete or check the running task → stop or done. Test hook for TT-5, TT-6, and TT-7: the launch argument `-debugStartTimerSeconds N` starts an N-second timer on an Inbox task named "Debug timer" at launch.
- **Acceptance:** fake-clock tests for every transition, including: pause keeps the remaining time, extend works in overtime (you go back to running), restore after quit, expiry during sleep fires once, and activeSeconds excludes pauses.

#### TT-5 · Menu bar item and popover (TOD-9)

- **Depends on:** TT-4. Can run in parallel with TT-6 and TT-7.
- **Scope:** `StatusItemController` shows the label for each state (decision 9, red `+m:ss` in overtime, name cut to 24 characters) and refreshes it every 1 s. A click toggles an `NSPopover` with `TimerPopoverView` (decision 10). "+custom" opens an inline field that uses `DurationParser`. Idle popover: "No timer running", a hint "New task: ⌃⌥Space", and "Quit TickTick". Leave space for "Open ↗" and "Open Notes" (TT-8 adds them) and "Settings…" (TT-11 adds it).
- **Acceptance:** you can drive a timer started with the TT-4 launch argument (`open -a TickTick --args -debugStartTimerSeconds 60`) through every state from the popover. It looks correct in light and dark mode, on the notched built-in display and on an external display.

#### TT-6 · Alarm: flash, sound, notification (TOD-10)

- **Depends on:** TT-4. Can run in parallel with TT-5 and TT-7.
- **Scope:** `FlashController` (decision 11, covers every screen and full-screen Spaces, Reduce Motion fade). `AlarmSound` plays "Glass". `NotificationController`: permission request on first launch, category with Done / +5 min / Stop, Time Sensitive level (with the fallback from Technical approach), scheduled ahead, and rescheduled or cancelled on every engine change. Actions route to `TimerEngine`. All three fire on the engine's `expired` event.
- **Acceptance:** a 1-minute timer flashes all displays 3 times, plays the sound, and shows the banner. This also works over a full-screen app, with Focus on, and after the Mac wakes from sleep past the end time. Each banner button does the right thing. Nothing fires twice.

#### TT-7 · Quick-add panel and global hotkey (TOD-11)

- **Depends on:** TT-4 (TT-3 for the parser). Can run in parallel with TT-5 and TT-6.
- **Scope:** `DurationPromptView`, the reusable "How long?" field (parser preview, 5 chip buttons, Return = start, Esc = skip). TT-9 uses it again. `QuickAddPanel`: a floating Spotlight-style `NSPanel` that the global ⌃⌥Space hotkey opens (`KeyboardShortcuts`, name `quickAdd`). Step 1: type the task, Return. Step 2: `DurationPromptView`, Return starts the timer. Esc on step 2 saves the task with no timer. Esc on step 1 closes. The task goes into Inbox. If a timer is running, it shows the switch confirmation inline.
- **Acceptance:** from any app, ⌃⌥Space → type → Return → `25` → Return starts a 25 min timer, and the menu bar shows it. The panel takes keyboard focus at once and closes on focus loss. **M1 is usable at this point.**

### M2 — Notes window

#### TT-8 · Notes window shell, sidebar, hybrid Dock (TOD-12)

- **Depends on:** TT-2 (and TT-5 for the popover buttons).
- **Scope:** `NotesWindow` (`NavigationSplitView`). Sidebar: Inbox first, then notes by `sortIndex`. ⌘N makes a new note, double-click renames, context-menu Delete asks for confirmation (not for Inbox). The detail pane shows the note title (a placeholder list until TT-9). `ActivationPolicyController` makes the Dock icon and Cmd-Tab appear while the window is open and disappear when it closes. Popover: add "Open Notes" (idle and active) and "Open ↗" (selects the running task's note).
- **Acceptance:** open and close the window 5 times, and the Dock icon appears and disappears each time. Cmd-Tab reaches the window. Notes survive a relaunch.

#### TT-9 · Task rows and the confirm flow (TOD-14)

- **Depends on:** TT-7 (`DurationPromptView`), TT-8.
- **Scope:** `NoteDetailView` + `TaskRowView`: checkbox, editable title, ▶ button on hover. A new empty row is always at the bottom. Return on a row saves it and shows `DurationPromptView` inline under it (decision 6). The prompt then creates the next empty row. ▶ opens the same prompt. Switch confirmation when a timer runs. ⌫ on an empty row deletes it and moves focus up. ↑ / ↓ move between rows. The running task's row shows a live indicator. Check the running task = Done. Delete the running task = stop.
- **Acceptance:** type 3 tasks: the first gets `25` + Return (timer starts), and the other two get Esc (no timer). Then ▶ on the third asks to switch. Every rule in "Behavior defaults" works in the UI.

#### TT-10 · Reorder, in-place completion, time badges (TOD-16)

- **Depends on:** TT-9.
- **Scope:** drag to reorder tasks, open and done (writes `sortIndex` through `TaskService`). A checked task stays in its row with a filled checkbox, like an Apple Notes checklist, and unchecking it leaves it there too (this replaces the "Completed (n)" section, on 2026-09-28). Badge `⏱ 45m est · 52m actual`: show only the parts that exist, and update the actual time live while the task's timer runs.
- **Acceptance:** reorder and completion survive a relaunch. The badges match the `TimerSession` data after a pause, an extend, and overtime.

### M3 — Settings, keyboard, polish

#### TT-11 · Settings window, launch at login, keyboard features (TOD-13)

- **Depends on:** TT-5, TT-7.
- **Scope:** `ShortcutCatalog` is one list of every shortcut (id, keys, description, scope). The handlers and the Help tab both read it, so the docs cannot drift. Popover keys: Space, D, S, 1, 5, 0. Global ⌃⌥T opens or closes the popover (`KeyboardShortcuts`, name `togglePopover`). Settings window (a `Settings` scene, opened from "Settings…" in the popover and with ⌘,). General tab: Launch at login toggle (`SMAppService.mainApp`). Shortcuts tab: on/off toggle + recorder for quick-add and open-popover, and an on/off toggle for popover keys. Toggles are saved in `UserDefaults` and take effect at once.
- **Acceptance:** each toggle turns its feature off and on with no relaunch. A rebound hotkey works at once. Launch at login survives a logout and login.

#### TT-12 · Help tab (TOD-15)

- **Depends on:** TT-11.
- **Scope:** a Help tab in Settings. It has short sections: Create a task, Time a task, The menu bar, The popover, When time is up, Notes, Settings. It also has a shortcuts table generated from `ShortcutCatalog`. The text uses plain language.
- **Acceptance:** every feature in "Product decisions" and every entry in `ShortcutCatalog` shows in the Help tab. A test asserts that every catalog entry has a description.

#### TT-13 · End-to-end QA and polish pass (TOD-17)

- **Depends on:** all other steps.
- **Scope:** run the full checklist in "Verification" below on the installed app. Fix every visual or behavior bug found: spacing, alignment, dark mode, truncation, focus rings, and animation glitches. Update the README with a feature list and a screenshot.
- **Acceptance:** the whole checklist passes, with no known UI defects left.

## Verification (full E2E checklist for TT-13, and a partial one for each step)

1. Clean clone → `scripts/setup.sh && make gen test lint install` → `⏱` shows in the menu bar and there is no Dock icon.
2. ⌃⌥Space → "Write cover letter" → Return → `1` → Return: the menu bar shows `⏱ Write cover letter · 0:59`, counting down.
3. Click the menu bar item: every popover field is correct. +1m, then Pause (the label shows `⏸`, time frozen), then Resume.
4. At zero: 3 flashes on every display, the Glass sound, and a banner. The label turns red and counts `+0:0x`.
5. Banner "+5 min" → running again. Wait for the next expiry → popover Done → the task is checked in Inbox.
6. Open Notes (the Dock icon appears). New note, 3 tasks, the confirm flow, a switch prompt, reorder, check and uncheck (the task stays in place), and est/actual badges.
7. Close Notes → the Dock icon goes away.
8. Start a 2 min timer, sleep the Mac for 3 min, wake it → the alarm fires once, and overtime shows about +1:00.
9. Start a timer, quit TickTick, relaunch → the timer is restored and correct.
10. Focus on → the alarm still flashes and plays the sound.
11. A full-screen app in front → the flash still covers it.
12. Settings: toggle each feature off and on, rebind a hotkey, launch at login. Help lists everything.
13. Light and dark mode, built-in and external display: no clipped or misaligned UI.
14. `make test lint` is green. Quit the app and kill every process you started.

## Later ideas (out of scope for v1)

- A remote control (URL scheme or AppleScript) and moving the `menubar-timer` MCP to TickTick.
- iCloud sync and an iPhone app.
- An alarm sound picker, a repeating alarm, and history and stats views.
- Search across notes.
