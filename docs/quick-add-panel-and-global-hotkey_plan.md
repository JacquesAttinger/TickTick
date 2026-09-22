# TT-7: Quick-add panel and global hotkey

<!-- Last edited: 2026-09-22 14:55 CDT -->

**TLDR:** We add the app's fastest path: press ⌃⌥Space in any app, and a small Spotlight-style box pops up.
You type a task, press Return, type how long it will take (for example `25`), press Return again, and the countdown starts.
The task lands in the Inbox note, and after this issue the timer app is usable end to end (milestone M1).

## Where to find it

Press ⌃⌥Space from any app (the hotkey works system-wide, with no window of TickTick open).
A floating panel appears centered on the screen where the mouse is.
Step 1 asks for the task name; Return moves to step 2, the "How long?" field with chips and a live preview; Return starts the timer.
Esc in step 2 keeps the task without a timer; Esc in step 1 closes without saving; clicking anywhere else closes the panel.

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, the TickTick menu-bar timeboxing app described in `docs/planning.md`.
On `origin/master` today only `README.md` and `docs/planning.md` exist: the whole dependency chain TT-1 (scaffold, TOD-5) → TT-2 (model, TOD-6) / TT-3 (time code, TOD-7) → TT-4 (timer engine, TOD-8) is still in plan-stage sibling branches, none merged.
The planned folder layout gives this issue the `TickTick/QuickAdd/` folder: `QuickAddPanel.swift`, `QuickAddView.swift`, and `DurationPromptView.swift`.
This layer sits on top of three planned interfaces: `TaskService.createTask(title:in:at:)` and the Inbox note from TT-2, `DurationParser.parse` and `TimeFormatting` (`preview`, `human`) from TT-3, and `TimerEngine.start(task:seconds:replacing:)` with its `.needsConfirmation(current:)` switch rule from TT-4.
Product decision 6 defines the confirm flow, decision 7 the duration input and preview, decision 8 the switch confirmation, and decision 15 the global hotkey (default ⌃⌥Space, task goes to Inbox).
TT-1's `project.yml` already declares the `KeyboardShortcuts` SPM package, so no project change is needed for the hotkey.

## What is wrong and why

Nothing is broken; this is the last M1 feature gap.
After TT-4 merges a timer can run, and after TT-5 merges it shows in the menu bar, but there is still no way for the user to create a task and start a timer — only the debug launch argument.
The shape of the work:

1. `DurationPromptView`, a self-contained SwiftUI "How long?" field: text input, live preview `= 1 h 30 min · ends 3:42 PM` or a quiet "Not a duration" hint, chips 5m / 15m / 25m / 45m / 60m that start at once, Return = start (valid input only), Esc = skip.
   It talks only through callbacks (`onStart(seconds:)`, `onSkip`), so TT-9 can drop it into the Notes window unchanged.
2. `QuickAddPanel`, a borderless non-activating `NSPanel` subclass that can become key without activating the app, floats above other windows, joins all Spaces, and closes when it loses key status.
3. `QuickAddView`, the SwiftUI panel content: step 1 (task title field) → step 2 (`DurationPromptView`) → an inline switch confirmation when a timer is already active.
4. `QuickAddController`, which registers the ⌃⌥Space hotkey (`KeyboardShortcuts`, name `quickAdd`), builds and positions the panel on the active screen, creates the task in Inbox, and drives `TimerEngine`.
5. A pure `QuickAddFlow` state machine behind the view, so every Return / Esc / chip / focus-loss / confirm rule is unit-testable without a panel on screen.

## Likely touched files

- `TickTick/QuickAdd/DurationPromptView.swift` — new; the reusable "How long?" SwiftUI view plus a small pure `DurationPromptModel` for the preview text.
- `TickTick/QuickAdd/QuickAddView.swift` — new; the two-step panel content and the inline switch confirmation.
- `TickTick/QuickAdd/QuickAddPanel.swift` — new; the non-activating floating `NSPanel` subclass and its screen-placement logic.
- `TickTick/QuickAdd/QuickAddController.swift` — new; hotkey registration, panel lifecycle, task creation, and engine calls (see "Decisions made alone" for why this fourth file exists).
- `TickTick/QuickAdd/QuickAddFlow.swift` — new; the pure state machine for the step and confirmation logic.
- `TickTick/App/AppDelegate.swift` — edited (from TT-1, rewritten by TT-4/TT-5); a few lines that build `QuickAddController` at launch.
- `TickTick/Model/TaskService.swift` — edited only if it still lacks an Inbox accessor and a `task(withID:)` query when this issue implements (see decisions).
- `TickTickTests/DurationPromptModelTests.swift` — new; preview and hint text per input.
- `TickTickTests/QuickAddFlowTests.swift` — new; every step transition and effect.
- `docs/quick-add-panel-and-global-hotkey_plan.md` — this plan.

## Plan

0. **Sync the branch.**
   Run `git fetch` and merge `origin/master` into this branch.
   Confirm the TT-4 code is present (`TickTick/Timer/TimerEngine.swift` with `start(task:seconds:replacing:)`, plus `TickTick/Time/` and `TickTick/Model/`) and that `make gen build test lint` passes before any new code.
   If TT-4 (TOD-8) has not merged, stop and report the unmet dependency instead of coding against a guessed API.
   If the merged APIs differ from the shapes assumed here (names, the `.needsConfirmation` payload, the Inbox accessor), adapt to the real APIs and note the deltas in the PR description.
1. **Duration prompt commit.**
   Add `TickTick/QuickAdd/DurationPromptView.swift`.
   A pure `DurationPromptModel` maps the raw input string to one of three display states: empty input → no preview, `DurationParser.parse` success → `TimeFormatting.preview(seconds:now:locale:timeZone:)` text, failure → the quiet hint "Not a duration".
   The view holds a focused `TextField` ("How long? 25, 1h30, 1:30…"), the preview line under it (secondary color for the preview, tertiary for the hint), and a chip row of 5 buttons labeled `5m 15m 25m 45m 60m`.
   Return (`.onSubmit`) calls `onStart(seconds:)` only when the input parses; with invalid input it does nothing.
   Esc (`.onExitCommand`) calls `onSkip`.
   A chip click calls `onStart` at once with its minutes × 60.
   The view takes only data and callbacks — no engine, no panel, no model store — so TT-9 can reuse it.
   Add `TickTickTests/DurationPromptModelTests.swift` with a fixed locale, time zone, and `now`: empty, valid (`25`, `1h30`), and invalid (`abc`, `25h`) inputs.
2. **Flow state machine commit.**
   Add `TickTick/QuickAdd/QuickAddFlow.swift`: a pure struct with a `step` (`.task`, `.duration(taskTitle:)`, `.confirmSwitch(pendingSeconds:)`) and a `mutating func handle(_ event:) -> [Effect]`.
   Events: `submitTask(String)`, `startRequested(seconds:)`, `skipDuration`, `escapeOnTask`, `engineNeedsConfirmation`, `confirmSwitch`, `cancelSwitch`, `focusLost`.
   Effects: `createTask(title:)`, `startTimer(seconds:replacing:)`, `close`.
   Rules encoded here: `submitTask` with a whitespace-only title does nothing; a valid title emits `createTask` and moves to `.duration`; `startRequested` emits `startTimer(replacing: false)`; `engineNeedsConfirmation` moves to `.confirmSwitch`; `confirmSwitch` emits `startTimer(replacing: true)` and `close`; `cancelSwitch` returns to `.duration` with the input kept; `skipDuration` and `focusLost` after step 1 emit only `close` (the task is already saved); `escapeOnTask` and `focusLost` on step 1 emit `close` with no task.
   Add `TickTickTests/QuickAddFlowTests.swift` with one test per rule above.
3. **Panel and view commit.**
   Add `TickTick/QuickAdd/QuickAddPanel.swift`: an `NSPanel` subclass with `styleMask [.borderless, .nonactivatingPanel]`, `canBecomeKey` overridden to true, `isFloatingPanel = true`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, a clear background, and a `show(on:)` helper that centers the ~560 pt panel horizontally and places it in the top third of the given screen.
   Add `TickTick/QuickAdd/QuickAddView.swift`: a rounded-rectangle `.regularMaterial` card that switches on the flow step — step 1 is a large borderless `TextField` ("New task…") with `.onSubmit` and `.onExitCommand`; step 2 shows the saved task title small on top and `DurationPromptView` under it; the confirmation state shows `Stop "A" (12 min left) and start "B"?` with a prominent "Stop & Start" button (Return) and a "Cancel" button (Esc).
   The confirmation line builds its remaining text from the engine's current state through `TimeFormatting.human` (`12 min left`, or `2 min over` in overtime).
   Materials and semantic colors only, so light and dark mode both look right.
4. **Controller, hotkey, and app wiring commit.**
   Add `TickTick/QuickAdd/QuickAddController.swift` (`@MainActor` final class):
   - Declares `KeyboardShortcuts.Name.quickAdd` with the default shortcut ⌃⌥Space and registers `onKeyUp` to toggle the panel (open if closed, close if open).
   - On open: builds a fresh `QuickAddFlow`, hosts `QuickAddView` in the panel via `NSHostingView`, shows it on the screen containing the mouse pointer (fallback `NSScreen.main`), and makes it key so typing lands in the field at once.
   - Runs the flow's effects: `createTask` appends to the Inbox note through `TaskService` and keeps the returned `TaskItem`; `startTimer` sets the task's `estimateSeconds` and calls `engine.start(task:seconds:replacing:)`, feeding a `.needsConfirmation` result back into the flow as an event; `close` orders the panel out.
   - Observes `NSWindow.didResignKeyNotification` for the panel and feeds `focusLost` into the flow.
   Edit `TickTick/App/AppDelegate.swift`: build one `QuickAddController` at launch with the shared `TaskService` and `TimerEngine`; keep the edit to those few lines to limit merge conflicts with TT-5's parallel `AppDelegate` rewrite.
   If `TaskService` still lacks an Inbox accessor or a `task(withID:)` query on the merged master, add the minimal query to `TickTick/Model/TaskService.swift` with a matching test in `TickTickTests/TaskServiceTests.swift`.
5. **Manual verification and polish commit.**
   Run the full Verification list below on the installed app and fix what looks wrong: focus not landing in the field, panel position, dark-mode contrast, chip spacing, preview flicker.
   Finishing pass: every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file over 500 lines, no function over 75 lines, `make test lint` green, push, and open the PR linked to TOD-11.

## Decisions made alone

- **Blocked-dependency handling:** TT-4 and its whole chain are unmerged plan-stage branches, so step 0 makes "merge a master that contains TT-4" a hard precondition and hard-stops otherwise — the same call every sibling plan (TT-2, TT-3, TT-4, TT-5) made, because coding against guessed APIs produces an unbuildable branch.
- **The task is created at step-1 Return, not at the end of the flow.**
  Reason: the scope says Esc on step 2 "saves the task with no timer", and creating the task before step 2 makes that rule and the focus-loss rule fall out for free; a deferred create would lose the task when the panel loses focus during step 2.
- **Focus loss behaves like Esc for the current step:** on step 1 it closes with nothing saved, on step 2 or the confirmation it closes with the task kept and no timer started.
  Reason: the scope only says "the panel closes when it loses focus"; mapping it to the Esc semantics of the current step is the least surprising reading.
- **Two extra files beyond the planned three (`QuickAddController.swift`, `QuickAddFlow.swift`).**
  Reason: sources are globbed so new files cost nothing; the controller separates AppKit lifecycle from SwiftUI content, and a pure flow struct is the only way to unit-test the Return / Esc / confirm rules without driving a real panel — the same split TT-5's plan chose for its label builder.
- **The hotkey toggles:** ⌃⌥Space with the panel already open closes it.
  Reason: that is Spotlight's behavior for the same gesture, and the scope names the panel Spotlight-style.
- **"Active screen" means the screen containing the mouse pointer,** fallback `NSScreen.main`.
  Reason: the app is a menu-bar accessory with no key window of its own most of the time, so "the screen with keyboard focus" is often undefined; the mouse screen is what Spotlight-like launchers use.
- **Panel placement is top third, not dead center.**
  Reason: "centered on the active screen" in the scope reads as horizontal centering of a Spotlight-style panel, and Spotlight itself sits in the upper third; a vertically dead-centered panel would cover the likely work area.
- **A non-activating panel (`.nonactivatingPanel`) instead of activating the app.**
  Reason: the panel must take keyboard focus "at once" from any app and give it back on close; a non-activating key panel does exactly that without deactivating the frontmost app or bouncing the Dock.
- **Empty or whitespace-only task title: Return does nothing.**
  Reason: an empty task row in Inbox would be junk; staying in step 1 is quieter than an error.
- **Cancel on the switch confirmation returns to step 2 with the typed duration kept,** it does not close.
  Reason: the user said no to switching, not to the new task; keeping the input lets them Esc (keep the task) or reconsider, and closing would throw work away.
- **Quick-add sets `estimateSeconds` on the task when it starts the timer.**
  Reason: decision 14's badge needs `⏱ 45m est`, TT-4's engine plan never writes the estimate, and the moment the user commits a duration is the estimate; noted for TT-9 to do the same from its prompt.
- **The confirmation's remaining text uses `TimeFormatting.human` of the engine's remaining time** (`12 min left`), and an overtime timer shows `2 min over`.
  Reason: decision 8's wording shows minutes-granular text; the overtime case is unspecified, and "0 min left" would be false.
- **`KeyboardShortcuts.Name.quickAdd` lives in `QuickAddController.swift` for now.**
  Reason: it is the only shortcut name until TT-11, whose `ShortcutCatalog` is the planned central home; moving one static constant later is trivial.
- **Reopening the panel always starts fresh at step 1.**
  Reason: a quick-add tool should never resurface stale half-typed state; Spotlight behaves the same way.
- **No new persistence and no settings toggle here.**
  Reason: decision 15b puts the on/off toggle and the hotkey recorder in TT-11's Settings window; this issue ships only the default binding.

## Out of scope found

- **AppDelegate is a three-way merge hotspot** — TT-4, TT-5, and this issue all edit `TickTick/App/AppDelegate.swift` in parallel branches; whoever merges last resolves it. A tiny composition-root refactor could ease this, but it belongs to no current issue.
- **Estimate writing belongs in one place** — this issue and TT-9 both set `estimateSeconds` next to `engine.start`; if that duplication itches, a later issue could fold it into the engine or `TaskService`.
- **The hotkey recorder and enable toggle** — TT-11's Settings scope (decision 15b); only the default ⌃⌥Space ships here.
- **Menu bar feedback for the started timer** — TT-5 owns the label; until it merges, a started timer is only visible in `UserDefaults`.
- **Popover keyboard shortcuts and ⌃⌥T** — decision 15 lists them, TT-11 owns them.

## Verification

Run in the worktree after the step 0 merge:

- `make gen test lint` — exits 0; the new `DurationPromptModelTests` and `QuickAddFlowTests` suites run and pass.
- The test list must include, by name: whitespace-only title does nothing, Esc on step 1 closes without a task, Esc on step 2 keeps the task and starts nothing, chip starts at once, invalid input blocks Return, confirmation cancel returns to the duration step, confirmation confirm starts with `replacing: true`, focus loss matches the Esc rule of each step.
- `git diff origin/master --stat` — only files under `TickTick/QuickAdd/`, `TickTick/App/`, `TickTick/Model/` (Inbox accessor at most), `TickTickTests/`, and `docs/` change.

Manual check on the installed app (`make install`):

1. From another app (Finder frontmost), press ⌃⌥Space: the panel appears on the screen with the mouse, and typing lands in the field at once without the frontmost app deactivating.
2. Type `Write cover letter`, Return, `25`, Return: the timer starts (menu bar shows `⏱ Write cover letter · 24:5x` if TT-5 has merged; otherwise `defaults read com.jacquesattinger.TickTick` shows the active state), and the task is in Inbox.
3. In step 2 try `1h30`, `1:30`, `90 min` (preview updates live), and `abc` (quiet "Not a duration" hint, Return does nothing).
4. A chip click starts at once; Esc on step 2 saves the task with no timer; Esc on step 1 closes with no task; a click on another window closes the panel.
5. With a timer running (`open -a TickTick --args -debugStartTimerSeconds 300` if needed), quick-add a second task: the inline confirmation shows the running task's name and remaining time, Cancel keeps the old timer, Confirm switches to the new one.
6. ⌃⌥Space with the panel open closes it; the panel looks right in light and dark mode.
7. Quit TickTick and kill every process started.
