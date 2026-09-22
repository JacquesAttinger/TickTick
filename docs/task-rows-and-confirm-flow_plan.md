# TT-9: Task rows and the confirm flow

<!-- Last edited: 2026-09-22 14:38 CDT -->

**TLDR:** This issue turns the Notes window's placeholder into a real task list.
You type a task into an always-present empty row, press Return, and an inline "How long?" field appears under it — Return starts the timer, Esc keeps the task without one.
Every row gets a checkbox, an editable title, a ▶ button, arrow-key navigation, and a live "timer running" indicator, all usable with the keyboard alone.

## Where to find it

The app lives in the menu bar, so start at the `⏱` item.
Click `⏱` to open the popover, then click "Open Notes".
The Notes window opens with the sidebar on the left; select a note (Inbox is selected by default).
The right pane is this issue: the note's task rows, the empty row at the bottom to type into, and the inline duration prompt that appears on Return.

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, the TickTick menu-bar timeboxing app described in `docs/planning.md` (Swift 6 + SwiftUI, AppKit where needed, XcodeGen project, SwiftData storage).
On `origin/master` today only `README.md` and `docs/planning.md` exist: every dependency (TT-1 scaffold through TT-8 window shell) is still a plan-stage sibling branch, so this plan targets the interfaces those plans committed to, with a hard gate in step 0.
The area is `TickTick/Notes/`, the Notes window views: TT-8 ships `NotesWindow.swift`, `NoteSidebarView.swift`, and a `NoteDetailView.swift` whose detail pane is an explicit placeholder labeled for this issue.
The part this issue builds is that detail pane: the ordered list of open task rows plus the create-and-time flow.
The exact sections are `NoteDetailView.swift` (rewritten from the placeholder) and the new `TaskRowView.swift`, sitting on four planned interfaces:
`TaskService` from TT-2 (`createTask(title:in:at:)`, `renameTask`, `deleteTask`, `toggleDone`, `openTasks(in:)`), `TimerEngine` from TT-4 (`start(task:seconds:replacing:)` returning `.started` or `.needsConfirmation(current:)`, plus the `timerHooks` that make check-running = Done and delete-running = stop), `DurationPromptView` from TT-7 (callbacks `onStart(seconds:)` / `onSkip`, built to be reused here unchanged), and TT-7's inline switch-confirmation UI inside `QuickAddView`.
Product decision 5 defines the note model (ordered task rows, no free text), decision 6 the confirm flow, decision 8 the switch confirmation, and "Behavior defaults" the running-task rules.

## What is wrong and why

Nothing is broken; this is the feature gap that makes M2 real.
After TT-8 the Notes window opens but its detail pane is a static placeholder: no way to see, create, edit, check, or time tasks from the window.
The shape of the work:

1. A pure `TaskListFlow` state machine behind the view (the same split TT-7's `QuickAddFlow` and TT-5's label builder chose), so every Return / Esc / ⌫ / ▶ / arrow / confirm rule is unit-testable without a window.
   Its state is the focused row, the open prompt (which task), and the pending switch confirmation; its effects are `createTask`, `renameTask`, `deleteTask`, `startTimer(seconds:replacing:)`, and focus moves.
2. `TaskRowView`, one dumb row: checkbox, editable title `TextField`, ▶ shown on hover and on the focused row, a live indicator (pulsing ⏱ + time left) when this row's task is the running one, and a context menu with Delete.
3. `NoteDetailView` rewritten: the note's open tasks in order, the always-present empty draft row at the bottom, the inline `DurationPromptView` under the row being timed, the inline switch confirmation, and all keyboard wiring (`@FocusState`, `.onSubmit`, `.onExitCommand`, `.onKeyPress` for ⌫ and ↑/↓).
4. The switch confirmation extracted from TT-7's `QuickAddView` into a small reusable view, so both entry points show the identical prompt.

The behavior defaults come almost for free: TT-4's `timerHooks` already turn `toggleDone` on the running task into Done and `deleteTask` into a stop with outcome `deleted`, so this issue only calls the plain `TaskService` operations.
Rename-updates-the-menu-bar-live falls out of TT-5's 1 s label refresh as long as its controller reads the task title on each tick; step 5 verifies that and makes the minimal fix if the title is cached.

**Dependency gate:** nothing below builds until `master` contains TT-1 through TT-8 (TT-9 is the sink of the whole M2 graph).
Step 0 checks for the concrete files and stops with a blocked report instead of coding against guessed APIs — the same call every sibling plan made.

## Likely touched files

- `TickTick/Notes/TaskListFlow.swift` — new; the pure state machine for focus, prompt, confirmation, and keyboard rules.
- `TickTick/Notes/TaskRowView.swift` — new; one task row (checkbox, title field, hover ▶, live indicator, context menu).
- `TickTick/Notes/NoteDetailView.swift` — rewritten from TT-8's placeholder; the row list, draft row, inline prompt, and all wiring to `TaskService` and `TimerEngine`.
- `TickTick/QuickAdd/SwitchConfirmationView.swift` — new (extracted); the shared "Stop "A" (12 min left) and start "B"?" view, reused here and by `QuickAddView`.
- `TickTick/QuickAdd/QuickAddView.swift` — edited; its inline confirmation block is replaced by the extracted view, behavior unchanged.
- `TickTick/MenuBar/StatusItemController.swift` — edited only if step 5 finds the label caches the task title; the fix is to read the title per refresh tick.
- `TickTickTests/TaskListFlowTests.swift` — new; one test per keyboard and flow rule.
- `docs/task-rows-and-confirm-flow_plan.md` — this plan.

## Plan

0. **Sync and gate.**
   Run `git fetch` and merge `origin/master` into this branch.
   Confirm these exist and `make gen build test lint` passes: `TickTick/Model/TaskService.swift` (TT-2), `TickTick/Timer/TimerEngine.swift` (TT-4), `TickTick/QuickAdd/DurationPromptView.swift` (TT-7), and `TickTick/Notes/NoteDetailView.swift` (TT-8).
   If any dependency has not merged, stop and report the unmet dependency instead of coding against a guessed API.
   If the merged APIs differ from the shapes assumed here (operation names, the `.needsConfirmation` payload, the focus or selection plumbing TT-8 shipped), adapt to the real APIs and note the deltas in the PR description.
1. **Shared switch confirmation commit.**
   If TT-7 already shipped its confirmation as a separate view, reuse it and skip the extraction.
   Otherwise move the confirmation block out of `TickTick/QuickAdd/QuickAddView.swift` into `TickTick/QuickAdd/SwitchConfirmationView.swift`: it takes the running task's name, the remaining-or-overtime text (built by the caller through `TimeFormatting.human`), the new task's title, and `onConfirm` / `onCancel` callbacks.
   Keep `QuickAddView`'s behavior identical and its `QuickAddFlowTests` green.
2. **Flow state machine commit.**
   Add `TickTick/Notes/TaskListFlow.swift`: a pure struct with the row list (task IDs plus the draft row), a `focus` (a row or the draft), an optional `prompt(taskID:)`, an optional `confirmSwitch(taskID: pendingSeconds:)`, and `mutating func handle(_ event:) -> [Effect]`.
   Events: `submitDraft(title:)`, `submitRow(id: title:)`, `playTapped(id:)`, `startRequested(seconds:)`, `skipDuration`, `engineNeedsConfirmation`, `confirmSwitch`, `cancelSwitch`, `deleteBackwardOnEmpty(id:)`, `deleteBackwardOnEmptyDraft`, `moveUp`, `moveDown`, `rowDeleted(id:)`.
   Rules encoded here (the reasons live under "Decisions made alone"):
   a whitespace-only draft Return does nothing; a valid draft Return emits `createTask` (appended at the end) and opens the prompt on the new task;
   Return on an existing row commits the rename and moves focus down;
   ▶ opens the prompt on that row (closing any other open prompt);
   `startRequested` emits `startTimer(replacing: false)` plus the estimate write, closes the prompt, and focuses the draft;
   `engineNeedsConfirmation` swaps the prompt for the confirmation; `confirmSwitch` emits `startTimer(replacing: true)`; `cancelSwitch` returns to the prompt with the typed input kept;
   `skipDuration` closes the prompt and focuses the draft;
   ⌫ on an empty existing row emits `deleteTask` and focuses the row above; ⌫ on the empty draft row only moves focus up;
   ↑ / ↓ move focus one row, clamped at the ends, with the draft row as the last stop.
   Add `TickTickTests/TaskListFlowTests.swift` with one Swift Testing case per rule above, plus "focus is never nil after any event sequence".
3. **Task row view commit.**
   Add `TickTick/Notes/TaskRowView.swift`, a dumb view over one `TaskItem` plus flags (`isFocused`, `isRunning`, remaining text) and callbacks.
   Checkbox: an SF Symbols button (`circle` / `checkmark.circle.fill`, `.accentColor` when done) calling `onToggleDone`.
   Title: a borderless `TextField` bound to a local draft string; commit through `onRename` on submit or focus loss; an emptied existing title reverts to the old one (TT-8's rename rule).
   ▶: visible when the row is hovered (`onHover`) or focused, `.buttonStyle(.plain)`, calling `onPlay`.
   Live indicator: shown when `isRunning`; a `TimelineView(.periodic(from:by:1))` renders ⏱ plus the time left through `TimeFormatting.countdown` (`+m:ss` red via `.overtime` past zero), with a slow opacity pulse that turns off under Reduce Motion.
   Long titles truncate with `.truncationMode(.tail)` while editing is not active and wrap naturally while editing.
   Context menu: one Delete item calling `onDelete`.
4. **Detail pane wiring commit.**
   Rewrite `TickTick/Notes/NoteDetailView.swift` around `TaskListFlow`: a `ScrollView` + `LazyVStack` of `TaskRowView`s from `taskService.openTasks(in:)`, the draft row at the bottom, and — under the row named by the flow state — `DurationPromptView` (reused unchanged from TT-7) or `SwitchConfirmationView`.
   Focus: one `@FocusState` keyed by row identity, driven from the flow's focus and reported back on user clicks.
   Keyboard: `.onSubmit` per field for Return, `.onExitCommand` for Esc in the prompt, `.onKeyPress(.upArrow/.downArrow)` for row moves, and `.onKeyPress(.delete)` (checked against empty text) for the ⌫ rules.
   Effects run against the real services: `createTask` appends through `TaskService`; `startTimer` sets `estimateSeconds` on the task and calls `engine.start(task:seconds:replacing:)`, feeding a `.needsConfirmation` result back into the flow as an event (the same wiring TT-7's controller uses).
   Checking and deleting call plain `toggleDone` / `deleteTask`; TT-4's hooks handle the running task.
   A checked task leaves the open list at once (TT-10 adds the Completed section).
   Scroll the focused row into view with `ScrollViewReader` when focus moves.
5. **Live-rename check commit (only if needed).**
   With a timer running, rename the running task in the window and watch the menu bar.
   If the label does not update within its 1 s refresh, make the minimal fix in `TickTick/MenuBar/StatusItemController.swift`: resolve the task title from `TaskService` on each tick instead of caching it at start, with a matching assertion in `StatusItemLabelTests` only if the label builder itself changes.
   Skip the commit entirely if TT-5's code already reads the title per tick.
6. **Manual verification and polish commit.**
   Run the full Verification list below on the installed app and fix what looks wrong: focus jumps, prompt alignment, hover flicker on ▶, dark-mode contrast, indicator pulse timing, truncation.
   Finishing pass: every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file over 500 lines, no function over 75 lines, `make test lint` green, push, and open the PR linked to TOD-14.

## Decisions made alone

- **Blocked-dependency handling:** every dependency (TT-1 through TT-8) is an unmerged plan-stage branch, so step 0 makes "merge a master that contains them" a hard precondition and hard-stops otherwise — the same call every sibling plan made, because coding against guessed APIs produces an unbuildable branch.
- **The draft row is UI-only, not a persisted empty `TaskItem`.**
  Reason: decision 5 says a note is a list of tasks, and persisting an empty task per note would leak junk rows into the data and the quick-add flow; the task is created at Return, exactly like TT-7 creates it at step-1 Return.
- **Return on an existing row commits the rename and moves focus down; the prompt on existing rows comes only from ▶.**
  Reason: the scope's Return rule describes the new-task flow (decision 6 says "Return on a new task"), and it lists ▶ as the way to time any row; Return-opens-prompt on every rename would make fixing a typo start the timer flow.
- **Focus loss on a non-empty draft row saves the task with no timer and no prompt.**
  Reason: the scope only defines Return; discarding typed work on a stray click would lose data, and this mirrors TT-8's commit-on-focus-loss rename rule and TT-7's focus-loss-keeps-the-task rule.
- **⌫ deletes only when the row's text is empty, and the draft row is never deleted (⌫ there just moves focus up).**
  Reason: the scope says "⌫ on an empty row deletes it", and "there is always one empty row at the bottom" forbids deleting the draft.
- **Task delete has no confirmation dialog (context menu Delete acts at once).**
  Reason: TT-8's confirmation guards a note (many tasks die); one task is one line and cheap to retype, and the scope names no dialog.
  Deleting the running task still stops the timer through TT-4's hook.
- **The switch confirmation is extracted from `QuickAddView` into a shared `SwitchConfirmationView` in `TickTick/QuickAdd/`.**
  Reason: the issue says "the same as TT-7", and one view is the only way the two prompts cannot drift; it stays in `TickTick/QuickAdd/` next to `DurationPromptView` because the planned folder layout has no shared-views folder and TT-9 already imports from there.
- **Cancel on the switch confirmation returns to the duration prompt with the typed input kept.**
  Reason: TT-7 decided exactly this for the same dialog, and the issue demands the flows match.
- **`estimateSeconds` is written next to `engine.start`, the same as TT-7.**
  Reason: TT-7's plan sets the estimate at start and explicitly notes "for TT-9 to do the same"; TT-7 also filed the fold-into-one-place cleanup as out of scope, so this issue copies the pattern instead of refactoring mid-flight.
- **"Selected row" means the row holding keyboard focus.**
  Reason: the pane has no separate selection model; with a `ScrollView` list the focused row is the only "current" row, so ▶ shows on hover or focus.
- **`ScrollView` + `LazyVStack` instead of `List`.**
  Reason: the flow needs full control of per-row focus, inline prompt insertion under an arbitrary row, and custom ⌫/↑/↓ handling, all of which fight `List`'s built-in selection and row focus on macOS; TT-10's drag reorder can use `.draggable`/`.dropDestination` or revisit the container.
- **Only open tasks render; a checked task disappears from the pane immediately.**
  Reason: the Completed section, uncheck-returns-to-position UI, and est/actual badges are all TT-10's scope; rendering `openTasks(in:)` keeps this issue's surface minimal, and the uncheck rule stays covered by TT-2's unit tests until TT-10 gives it a UI.
- **The running row's time left refreshes through `TimelineView(.periodic(from:by:1))` and pauses its pulse under Reduce Motion.**
  Reason: TT-5 already established a 1 s UI cadence reading the engine's absolute `endDate`; `TimelineView` is the SwiftUI-native equivalent without hand-rolled timers, and the accessibility setting mirrors the flash's Reduce Motion rule.
- **The pure-flow split (`TaskListFlow` behind the view).**
  Reason: the planned folder layout names only two files, but sources are globbed so a new file costs nothing, and a pure struct is the only way to unit-test the keyboard and confirm rules without driving a window — the same split TT-7 (`QuickAddFlow`) and TT-5 (label builder) chose.
- **The behavior defaults ride on TT-4's hooks; this issue adds no running-task special cases.**
  Reason: TT-4's `timerHooks` already map `toggleDone` on the running task to Done and `deleteTask` to a stop with outcome `deleted`; duplicating that logic in the view would create two owners of one rule.
- **Live rename is verified against TT-5's refresh and only patched if the title is cached.**
  Reason: the label rebuilds every second from engine state plus the task name; whether the name is fetched per tick is TT-5's implementation detail, unknowable until it merges, so the plan budgets a conditional minimal fix instead of a speculative rewrite.

## Out of scope found

- **Drag reorder, the Completed section, and est/actual badges** — TT-10 (TOD-16) owns all three; this pane renders open tasks only.
- **The uncheck rule has no UI until TT-10** — "uncheck returns the task to its old position" cannot be exercised on screen while no Completed section exists; TT-2's unit tests keep it covered.
- **Estimate writing is duplicated in two call sites** — TT-7 already filed folding `estimateSeconds` into the engine or `TaskService`; this issue adds the second call site the cleanup would collapse.
- **`QuickAdd/` is drifting into a shared-components folder** — `DurationPromptView` and now `SwitchConfirmationView` are cross-feature views living under a feature folder; a `TickTick/Shared/` move is a later cosmetic refactor.
- **No multi-row operations** — the pane has no multi-select, so bulk delete or bulk check is absent; nothing in the planning doc asks for it.

## Verification

Run in the worktree after the step 0 merge:

- `make gen test lint` — exits 0; the new `TaskListFlowTests` suite runs and passes, and every pre-existing suite stays green.
- The test list must include, by name: whitespace-only draft Return does nothing, draft Return creates the task and opens the prompt, prompt Return starts with `replacing: false`, Esc keeps the task and starts nothing, confirmation confirm starts with `replacing: true`, confirmation cancel returns to the prompt with input kept, ⌫ on an empty row deletes it and focuses the row above, ⌫ on the draft only moves focus up, arrows clamp at both ends, focus is never nil.
- `git diff origin/master --stat` — only files under `TickTick/Notes/`, `TickTick/QuickAdd/`, `TickTick/MenuBar/` (step 5 at most), `TickTickTests/`, and `docs/` change.

Manual check on the installed app (`make install`), all of it keyboard-only except the hover and context-menu checks:

1. Open Notes, select Inbox, and click into the empty row.
   Type "Write intro", Return, `25`, Return: the timer starts, the menu bar shows `⏱ Write intro · 24:5x`, the row shows the pulsing ⏱ with the time left, and focus sits in the new empty row.
2. Type "Outline", Return, Esc, then "Research", Return, Esc: both tasks save with no timer, and focus lands back in the empty row each time.
3. Press ↑ twice to reach "Research", press nothing but keys to reach its ▶ (focused row shows ▶), activate it: the confirmation asks to stop "Write intro" with its remaining time; Cancel keeps the old timer, reopening and confirming switches, and the live indicator moves to "Research".
4. Check the running task's checkbox: the timer ends as Done and the row leaves the list.
5. Start another timer, delete its row from the context menu: the timer stops and the menu bar returns to `⏱`.
6. Start a timer, rename its row while it runs: the menu bar label shows the new name within a second.
7. ⌫ housekeeping: clear an existing row's title and press ⌫ (the row dies, focus moves up), and press ⌫ in the empty bottom row (focus moves up, the row stays).
8. Give one task a very long title: it truncates cleanly in the row and wraps while editing, in light mode and dark mode.
9. Walk the whole flow again in dark mode; focus is visible at every step and never disappears.
10. Quit TickTick and kill every process started during the checks.
