# TT-7: Quick-add panel and global hotkey

<!-- Last edited: 2026-09-24 18:40 PT -->

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
TT-1 (scaffold), TT-2 (model), TT-3 (time code), and TT-4 (timer engine) are on `origin/master`.
TT-5 (menu bar, PR #16) and TT-6 (alarm, PR #17) are still open, so this branch also merges the TT-6 code branch `jacques/tod-10-tt-6-alarm-screen-flash-sound-notification-code`, which contains TT-5.
This issue owns the `TickTick/QuickAdd/` folder.
It sits on top of `TaskService.createTask(title:in:at:)`, `TaskService.setEstimate(_:for:)`, and `ModelStore.bootstrapInbox()` from TT-2, `DurationParser.parse` and `TimeFormatting` (`preview`, `human`) from TT-3, and `TimerEngine.start(task:seconds:replacing:)` with its `.needsConfirmation(current:)` result from TT-4.
Product decision 6 defines the confirm flow, decision 7 the duration input and preview, decision 8 the switch confirmation, and decision 15 the global hotkey (default ⌃⌥Space, task goes to Inbox).
TT-1's `project.yml` already declares the `KeyboardShortcuts` SPM package (3.1.0 resolves), so no project change is needed for the hotkey.

## What is wrong and why

Nothing is broken; this is the last M1 feature gap.
A timer can run and it shows in the menu bar, but there is still no way for the user to create a task and start a timer — only the debug launch argument.
The shape of the work:

1. `DurationPromptView`, a self-contained SwiftUI "How long?" field: text input, live preview `= 1 h 30 min · ends 3:42 PM` or a quiet "Not a duration" hint, chips 5m / 15m / 25m / 45m / 60m that start at once, Return = start (valid input only), Esc = skip.
   It talks only through callbacks (`onStart(seconds:)`, `onSkip`), so TT-9 can drop it into the Notes window unchanged.
2. `QuickAddPanel`, a borderless non-activating `NSPanel` subclass that can become key without activating the app, floats above other windows, joins all Spaces, and closes when it loses key status.
3. `QuickAddView`, the SwiftUI panel content: step 1 (task title field) → step 2 (`DurationPromptView`) → an inline switch confirmation when a timer is already active.
4. `QuickAddController`, which registers the ⌃⌥Space hotkey (`KeyboardShortcuts`, name `quickAdd`), builds and positions the panel on the active screen, creates the task in Inbox, and drives `TimerEngine`.
5. A pure `QuickAddFlow` state machine behind the view, so every Return / Esc / chip / focus-loss / confirm rule is unit-testable without a panel on screen.

## Touched files

- `TickTick/QuickAdd/DurationPromptView.swift` — new; the reusable "How long?" SwiftUI view plus the pure `DurationPromptModel` for the preview line. The model reuses `CustomExtendEntry` from the popover's `+custom` field, so both fields read text the same way.
- `TickTick/QuickAdd/QuickAddFlow.swift` — new; the pure state machine for the step and confirmation rules.
- `TickTick/QuickAdd/SwitchConfirmation.swift` — new; the pure switch question text and `SwitchConfirmationView` (Cancel / Stop & Start). TT-9 can use both.
- `TickTick/QuickAdd/QuickAddSession.swift` — new; one opening of the panel: the flow, the typed text, and the effects on `TaskService` and `TimerEngine`. Tests drive it on an in-memory store.
- `TickTick/QuickAdd/QuickAddView.swift` — new; the two-step panel content and the inline switch confirmation.
- `TickTick/QuickAdd/QuickAddPanel.swift` — new; the non-activating floating `NSPanel` subclass and its screen placement.
- `TickTick/QuickAdd/QuickAddController.swift` — new; hotkey registration, panel lifecycle, and focus-loss handling.
- `TickTick/App/AppDelegate.swift` — builds `QuickAddController` after the timer restore.
- `TickTick/MenuBar/TimerPopoverView.swift` — one comment: the idle hint "New task: ⌃⌥Space" is now real.
- `TickTickTests/DurationPromptModelTests.swift`, `QuickAddFlowTests.swift`, `QuickAddSessionTests.swift`, `SwitchConfirmationTests.swift`, `QuickAddPanelTests.swift` — new.
- `docs/quick-add-panel-and-global-hotkey_plan.md` — this plan.

## Plan

0. **Sync the branch.**
   Run `git fetch`, merge `origin/master`, then merge the TT-6 code branch (it contains TT-5).
   Confirm that `make test` passes before any new code.
   `TaskService.task(withID:)`, `TaskService.setEstimate(_:for:)`, and `ModelStore.bootstrapInbox()` already exist, so this issue adds nothing to `TickTick/Model/`.
1. **Duration prompt commit.**
   Add `TickTick/QuickAdd/DurationPromptView.swift`.
   A pure `DurationPromptModel` maps the raw input string to one of three display states: empty input → no preview, `DurationParser.parse` success → `TimeFormatting.preview(seconds:now:locale:timeZone:)` text, failure → the quiet hint "Not a duration".
   It reads the text through TT-5's `CustomExtendEntry`, so the `+custom` field and this field agree on what is empty and what is invalid.
   The view holds a focused `TextField` ("How long? 25, 1h30, 1:30…"), the preview line under it (secondary color for the preview, tertiary for the hint), and a chip row of 5 buttons labeled `5m 15m 25m 45m 60m`.
   Return (`.onSubmit`) calls `onStart(seconds:)` only when the input parses; with invalid input it does nothing.
   Esc (`.onExitCommand`) calls `onSkip`.
   A chip click calls `onStart` at once with its minutes × 60.
   The view takes only a `text` binding and callbacks — no engine, no panel, no model store — so TT-9 can reuse it.
   The caller owns `text`, so the typed duration survives when the switch question replaces the field.
   A `TimelineView(.everyMinute)` redraws the preview, so its "ends" time stays right.
   Add `TickTickTests/DurationPromptModelTests.swift` with a fixed locale, time zone, and `now`: empty, valid (`25`, `1h30`), and invalid (`abc`, `25h`) inputs.
2. **Flow state machine commit.**
   Add `TickTick/QuickAdd/QuickAddFlow.swift`: a pure struct with a `step` (`.task`, `.duration`, `.confirmSwitch(pendingSeconds:)`, `.closed`), a `taskTitle`, and a `mutating func handle(_ event:) -> [Effect]`.
   Events: `submitTask(String)`, `startRequested(seconds:)`, `skipDuration`, `escapeOnTask`, `timerStarted`, `engineNeedsConfirmation`, `confirmSwitch`, `cancelSwitch`, `focusLost`.
   Effects: `createTask(title:)`, `startTimer(seconds:replacing:)`, `close`.
   Rules encoded here: `submitTask` with a whitespace-only title does nothing; a valid title emits `createTask` with the trimmed title and moves to `.duration`; `startRequested` emits `startTimer(replacing: false)`; the engine's answer comes back as `timerStarted` (emits `close`) or `engineNeedsConfirmation` (moves to `.confirmSwitch`); `confirmSwitch` emits `startTimer(replacing: true)`, and its `timerStarted` closes; `cancelSwitch` returns to `.duration`; `skipDuration` and `focusLost` after step 1 emit only `close` (the task is already saved); `escapeOnTask` and `focusLost` on step 1 emit `close` with no task; in `.closed` every event does nothing, so a late focus loss cannot close twice.
   Add `TickTickTests/QuickAddFlowTests.swift` with one test per rule above.
3. **Panel and view commit.**
   Add `TickTick/QuickAdd/QuickAddPanel.swift`: an `NSPanel` subclass with `styleMask [.borderless, .nonactivatingPanel]`, `canBecomeKey` overridden to true, `isFloatingPanel = true`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, a clear background, a pure `frame(for:in:)` that centers the 560 pt panel horizontally with its top edge 22% of the visible height below the top, and `setHeight(_:)`, which keeps the top edge in place so the panel grows down.
   Add `TickTick/QuickAdd/QuickAddView.swift`: a rounded-rectangle `.thickMaterial` card that reports its height and switches on the flow step — step 1 is a large borderless `TextField` ("New task…") with `.onSubmit` and `.onExitCommand`; step 2 shows the saved task title small on top and `DurationPromptView` under it; the confirmation state is `SwitchConfirmationView` (`SwitchConfirmation.swift`): `Stop “A” (12 min left) and start “B”?` with a prominent "Stop & Start" button (Return) and a "Cancel" button (Esc).
   The confirmation line builds its remaining text from the engine's current state through `TimeFormatting.human` (`12 min left`, or `2 min over` in overtime), and redraws every second.
   Materials and semantic colors only, so light and dark mode both look right.
4. **Controller, hotkey, and app wiring commit.**
   Add `TickTick/QuickAdd/QuickAddController.swift` (`@MainActor` final class):
   - Declares `KeyboardShortcuts.Name.quickAdd` with the default shortcut ⌃⌥Space and registers `onKeyUp` to toggle the panel (open if closed, close if open).
   - On open: builds a fresh `QuickAddSession`, hosts `QuickAddView` in the panel via `NSHostingView`, shows it on the screen containing the mouse pointer (fallback `NSScreen.main`), and makes it key so typing lands in the field at once.
   - Observes `NSWindow.didResignKeyNotification` for the panel and feeds `focusLost` into the session. The hotkey on an open panel feeds `focusLost` too.
   Add `TickTick/QuickAdd/QuickAddSession.swift` (`@Observable`, `@MainActor`): it holds the flow and the typed text, and runs the flow's effects: `createTask` appends to the Inbox note through `TaskService` and keeps the returned `TaskItem`; `startTimer` calls `engine.start(task:seconds:replacing:)`, sets `estimateSeconds` only on `.started`, and feeds the result back as `timerStarted` or `engineNeedsConfirmation`; `close` calls the controller's close.
   Add `TickTickTests/QuickAddSessionTests.swift` on an in-memory store with a test clock.
   Edit `TickTick/App/AppDelegate.swift`: build one `QuickAddController` after the timer restore, with the shared `TaskService`, `TimerEngine`, and `ModelStore.bootstrapInbox`.
5. **Manual verification and polish commit.**
   Run the Verification list below on the Debug build and fix what looks wrong: focus not landing in the field, panel position, dark-mode contrast, chip spacing, preview flicker.
   Finishing pass: every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file over 500 lines, no function over 75 lines, `make test lint` green, push, and open the PR linked to TOD-11.

## Decisions made alone

- **The task is created at step-1 Return, not at the end of the flow.**
  Reason: the scope says Esc on step 2 "saves the task with no timer", and creating the task before step 2 makes that rule and the focus-loss rule fall out for free; a deferred create would lose the task when the panel loses focus during step 2.
- **Focus loss behaves like Esc for the current step:** on step 1 it closes with nothing saved, on step 2 or the confirmation it closes with the task kept and no timer started.
  Reason: the scope only says "the panel closes when it loses focus"; mapping it to the Esc semantics of the current step is the least surprising reading.
- **Four extra files beyond the planned three (`QuickAddController.swift`, `QuickAddFlow.swift`, `QuickAddSession.swift`, `SwitchConfirmation.swift`).**
  Reason: sources are globbed so new files cost nothing; the controller separates AppKit lifecycle from SwiftUI content, a pure flow struct is the only way to unit-test the Return / Esc / confirm rules without driving a real panel, the session lets tests run the effects on a real in-memory store, and the switch question is shared with TT-9.
- **The hotkey toggles:** ⌃⌥Space with the panel already open closes it.
  Reason: that is Spotlight's behavior for the same gesture, and the scope names the panel Spotlight-style.
- **"Active screen" means the screen containing the mouse pointer,** fallback `NSScreen.main`.
  Reason: the app is a menu-bar accessory with no key window of its own most of the time, so "the screen with keyboard focus" is often undefined; the mouse screen is what Spotlight-like launchers use.
- **Panel placement is top third, not dead center.**
  Reason: "centered on the active screen" in the scope reads as horizontal centering of a Spotlight-style panel, and Spotlight itself sits in the upper third; a vertically dead-centered panel would cover the likely work area.
- **A non-activating panel (`.nonactivatingPanel`) instead of activating the app.**
  Reason: the panel must take keyboard focus "at once" from any app and give it back on close; a non-activating key panel does exactly that without deactivating the frontmost app or bouncing the Dock.
  The E2E test confirmed it: unlike TT-5's popover, the panel needs no `NSApp.activate`, and it takes typing at once also over a full-screen app.
  The SwiftUI fields still set their focus after a 50 ms wait, the same fix TT-5 needed in the popover.
- **`.thickMaterial`, not `.regularMaterial`.**
  Reason: in dark mode over a bright window, the regular material let the page show through so much that the secondary text lost contrast.
- **Every step puts its text in one column after a fixed icon column** (timer, hourglass, swap arrows).
  Reason: without it, the text jumped left between step 1 and step 2.
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

- **AppDelegate is a merge hotspot** — TT-8, TT-9, and TT-11 will also add lines to `TickTick/App/AppDelegate.swift`. A tiny composition-root refactor could ease this, but it belongs to no current issue.
- **Estimate writing belongs in one place** — this issue and TT-9 both set `estimateSeconds` next to `engine.start`; if that duplication itches, a later issue could fold it into the engine or `TaskService`.
- **The hotkey recorder and enable toggle** — TT-11's Settings scope (decision 15b); only the default ⌃⌥Space ships here.
- **Popover keyboard shortcuts and ⌃⌥T** — decision 15 lists them, TT-11 owns them.

## Verification

Run in the worktree after the step 0 merge:

- `make test lint` — exits 0; the new `DurationPromptModelTests`, `QuickAddFlowTests`, `QuickAddSessionTests`, `SwitchConfirmationTests`, and `QuickAddPanelTests` suites run and pass.
- The test list must include, by name: whitespace-only title does nothing, Esc on step 1 closes without a task, Esc on step 2 keeps the task and starts nothing, chip starts at once, invalid input blocks Return, confirmation cancel returns to the duration step, confirmation confirm starts with `replacing: true`, focus loss matches the Esc rule of each step.
- The diff against the TT-6 code branch changes only files under `TickTick/QuickAdd/`, `TickTick/App/`, one comment in `TickTick/MenuBar/`, `TickTickTests/`, and `docs/`.

Manual check on the Debug build (`make build`, then `open build/Build/Products/Debug/TickTick.app`):

1. From another app (Finder frontmost), press ⌃⌥Space: the panel appears on the screen with the mouse, and typing lands in the field at once without the frontmost app deactivating.
2. Type `Write cover letter`, Return, `25`, Return: the timer starts (the menu bar shows `⏱ Write cover letter · 24:5x`, and `defaults read com.jacquesattinger.TickTick activeTimer` shows the active state), and the task is in Inbox.
3. In step 2 try `1h30`, `1:30`, `90 min` (preview updates live), and `abc` (quiet "Not a duration" hint, Return does nothing).
4. A chip click starts at once; Esc on step 2 saves the task with no timer; Esc on step 1 closes with no task; a click on another window closes the panel.
5. With a timer running (quit TickTick, then `open build/Build/Products/Debug/TickTick.app --args -debugStartTimerSeconds 300`), quick-add a second task: the inline confirmation shows the running task's name and remaining time, Cancel keeps the old timer, Confirm switches to the new one.
6. ⌃⌥Space with the panel open closes it; the panel looks right in light and dark mode.
7. Quit TickTick and kill every process started.
