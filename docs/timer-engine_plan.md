# TT-4: Timer engine

<!-- Last edited: 2026-09-22 14:22 CDT -->

**TLDR:** We build the app's "brain" for the one countdown timer: a small state machine that knows if a timer is idle, running, paused, or past zero (overtime).
It writes its state to disk on every change, so the timer survives a quit, a crash, or the Mac going to sleep.
There is no UI in this issue — fake-clock unit tests prove every rule, and a hidden launch argument lets the next three issues start a timer before the real "add task" UI exists.

## Where to find it

Not UI-reachable.
This issue is the timer logic layer: pure state code under `TickTick/Timer/`, plus small hooks in `TaskService` and the app startup.
TT-5 (menu bar and popover), TT-6 (alarm), and TT-7 (quick-add) put this engine on screen later.
The only way to poke it today is the launch argument `open -a TickTick --args -debugStartTimerSeconds 60`, which starts a 60-second timer on an Inbox task named "Debug timer".

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, the TickTick menu-bar timeboxing app described in `docs/planning.md`.
On `origin/master` today only `README.md` and `docs/planning.md` exist: TT-1 (TOD-5, the Xcode scaffold), TT-2 (TOD-6, the SwiftData model and `TaskService`), and TT-3 (TOD-7, the duration parser) have not merged, and TT-2 and TT-3 are still in the plan stage on their branches.
The planned folder layout gives this issue the `TickTick/Timer/` folder: `Clock.swift`, `TimerState.swift`, `TimerEngine.swift`, and `ActiveTimerStore.swift`.
The engine sits between the data layer (`TickTick/Model/TaskService.swift`, from TT-2) and the future UI: it owns the one active timer, records `TimerSession` rows through `TaskService`, and tells listeners when the timer expires.
Product decision 8 gives the one-timer switch rule, decision 10 the operations the popover needs, decision 12 the overtime behavior, decision 17 the sleep and relaunch rules, and "Behavior defaults" the check and delete rules for the running task.

## What is wrong and why

Nothing is broken; this is a feature gap.
No timer logic exists, and three parallel issues (TT-5, TT-6, TT-7) all need a working engine to build on.
The shape of the work, from `docs/planning.md` ("Technical approach → Timer engine") and the issue:

- A `Clock` protocol with a system clock and a hand-advanced test clock, so every rule is testable without waiting.
- A `TimerState` value type: `idle`, or an active timer that is `running(endDate)`, `paused(remaining)`, or `overtime(since)`, plus the task ID, planned seconds, and `startedAt`.
  It stores `endDate` or `remaining`, never a tick counter, so sleep and relaunch cannot make it drift.
- A `TimerEngine` (`@Observable`, `@MainActor`) with `start`, `pause`, `resume`, `extend`, `stop`, and `done`, the switch-confirmation rule, `TimerSession` bookkeeping through `TaskService`, and an `expired` event that fires exactly once when the timer enters overtime.
- An `ActiveTimerStore` that saves the state to `UserDefaults` on every change and restores it on launch, going straight to overtime (and firing `expired`) when the end passed while the app was quit.
- A re-check on `NSWorkspace.didWakeNotification`, hooks so that checking or deleting the running task acts like `done` or a delete-flavored `stop`, and the `-debugStartTimerSeconds` launch argument.

One gap in the dependency: TT-2's `TaskService` plan ships only note and task primitives and explicitly leaves session handling to TT-4.
So this issue also adds the session operations (`startSession`, `closeSession`, fetch by ID) to `TaskService`.

## Likely touched files

- `TickTick/Timer/Clock.swift` — new; `Clock` protocol (`var now: Date`), `SystemClock`, and `TestClock` with an `advance(by:)` you move by hand.
- `TickTick/Timer/TimerState.swift` — new; Codable `TimerState` (`.idle` / `.active(ActiveTimer)`) and the `ActiveTimer` struct with phase, task ID, session ID, planned seconds, `startedAt`, and the active-seconds bookkeeping fields.
- `TickTick/Timer/TimerEngine.swift` — new; the `@Observable @MainActor` state machine with all operations, the switch rule, session bookkeeping, and the single `expired` emission.
- `TickTick/Timer/ActiveTimerStore.swift` — new; `UserDefaults` save on every change, restore on launch, and the straight-to-overtime rule.
- `TickTick/Model/TaskService.swift` — edited (from TT-2); adds `startSession`, `closeSession`, `session(withID:)`, and the `timerHooks` protocol property for the check and delete rules.
- `TickTick/App/AppDelegate.swift` — edited (from TT-1); builds the engine at launch, restores state, observes `didWakeNotification`, and handles `-debugStartTimerSeconds`.
- `TickTickTests/TimerEngineTests.swift` — new; fake-clock tests for every transition and the session bookkeeping.
- `TickTickTests/ActiveTimerStoreTests.swift` — new; persistence round-trip and restore-after-quit tests.
- `docs/timer-engine_plan.md` — this plan.

## Plan

0. Sync the branch: `git fetch`, then merge `origin/master` so the TT-1 scaffold, the TT-2 model layer, and the TT-3 time code are present.
   If TT-1, TT-2, or TT-3 has not merged, stop and report the unmet dependency instead of inventing their code.
1. Add `TickTick/Timer/Clock.swift` and `TickTick/Timer/TimerState.swift`.
   `Clock` exposes `var now: Date`; `SystemClock` returns `Date()`; `TestClock` starts at a fixed date and has `advance(by seconds:)`.
   `TimerState` is `.idle` or `.active(ActiveTimer)`.
   `ActiveTimer` is Codable and holds `taskID: UUID`, `sessionID: UUID`, `plannedSeconds: TimeInterval`, `startedAt: Date`, `accumulatedActiveSeconds: TimeInterval`, `lastResumedAt: Date?` (nil while paused), and `phase: Phase` with `running(endDate: Date)`, `paused(remaining: TimeInterval)`, and `overtime(since: Date)`.
   Add Codable round-trip tests for every phase.
   Commit with its tests.
2. Add the session operations to `TickTick/Model/TaskService.swift`: `startSession(for:plannedSeconds:at:) -> TimerSession`, `closeSession(_:endedAt:activeSeconds:outcome:)`, and `session(withID:)`.
   Add their tests to `TickTickTests/TaskServiceTests.swift`, including "a closed session shows up in `actualSeconds(for:)`".
   Commit with its tests.
3. Add `TickTick/Timer/TimerEngine.swift` with the core transitions and session bookkeeping.
   `start(task:seconds:replacing:)` returns `.started` or `.needsConfirmation(current:)` and changes nothing on confirmation; with `replacing: true` it closes the old session as `replaced` first.
   `pause` (running only) stores `remaining` and folds the run time into `accumulatedActiveSeconds`; `resume` (paused only) sets `endDate = now + remaining`; `stop` closes the session as `stopped`; `done` closes it as `done` and checks the task through `TaskService`.
   Every mutation notifies a `stateDidChange` closure that `ActiveTimerStore` plugs into later.
   Add `TickTickTests/TimerEngineTests.swift` with a `TestClock` and an in-memory `ModelStore`: start, switch confirmation changes nothing, replace closes the old session as `replaced`, pause keeps the remaining time, resume, stop, and done checks the task.
   Commit with its tests.
4. Add expiry and overtime to the engine.
   `checkExpiry()` moves running past `endDate` to `overtime(since: endDate)` and fires the `onExpired` closure; the phase change itself guarantees the event fires only once.
   `extend(seconds:)` while running adds to `endDate`, while paused adds to `remaining`, and in overtime folds the overtime into `accumulatedActiveSeconds` and returns to `running(endDate: now + seconds)`.
   When built with `schedulesExpiry: true` (the app; tests pass false) the engine arms one wall-clock `Timer` for `endDate` and re-arms it on every pause, resume, and extend, and it re-checks on `NSWorkspace.didWakeNotification`.
   Extend the tests: extend while running, extend in overtime goes back to running, `expired` fires exactly once even when `checkExpiry()` runs twice, and `activeSeconds` counts running and overtime but not pauses (run 60 s, pause 30 s, resume 60 s, stop → 120 s).
   Commit with its tests.
5. Add `TickTick/Timer/ActiveTimerStore.swift` and the `TaskService` hooks.
   The store JSON-encodes `TimerState` into an injected `UserDefaults` on every `stateDidChange`, and `restore(into:)` reloads it at launch: a future `endDate` resumes running, a past one goes straight to overtime and fires `expired`, a persisted overtime phase does not fire again, and a missing task clears the state and closes the open session as `deleted`.
   `TaskService` gets a `timerHooks` protocol (`taskWasCompleted`, `taskWillBeDeleted`) that `toggleDone` and `deleteTask` call; the engine implements it so checking the running task runs `done` (with a re-entrancy guard) and deleting it closes the session with outcome `deleted`.
   Add `TickTickTests/ActiveTimerStoreTests.swift` (round-trip before the end, restore after the end fires `expired` once, restore of paused and overtime states, missing task) and the hook tests in `TimerEngineTests.swift`.
   Commit with its tests.
6. Wire the app in `TickTick/App/AppDelegate.swift`: build `ModelStore`, `TaskService`, `TimerEngine`, and `ActiveTimerStore` at launch, restore the saved state, and then handle `-debugStartTimerSeconds N` (read through the `UserDefaults` argument domain): reuse an open Inbox task named "Debug timer" or create one, and start an N-second timer with `replacing: true`.
   Commit, then run the finishing pass: every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file over 500 lines and no function over 75 lines, `make test lint` green, push, and open the PR linked to TOD-8.

## Decisions made alone

- **Blocked-dependency handling:** none of TT-1, TT-2, and TT-3 has merged, and TT-2 and TT-3 are plan-only branches, so step 0 makes "merge a master that contains all three" a hard precondition, the same call the TT-2 and TT-3 plans made; duplicating their code here would guarantee conflicts.
- **Session operations live in `TaskService`:** the issue says sessions are created and closed "through `TaskService`", and TT-2's plan explicitly left them out, so this issue adds them there instead of adding a second service.
- **State shape:** one Codable `ActiveTimer` struct with a nested `Phase` enum, instead of a flat four-case enum, because the task ID, session ID, planned seconds, and `startedAt` are common to all three active phases and `Codable` on a struct is simpler to persist.
- **Persisting `sessionID`:** the open `TimerSession` row's ID is part of the saved state, so after a quit or crash the engine can close the same row instead of leaking an open one.
- **Active-seconds bookkeeping:** the state stores `accumulatedActiveSeconds` plus `lastResumedAt`; active time is the sum plus `now - lastResumedAt` while running or in overtime, and `lastResumedAt` is nil while paused, which makes "pauses do not count" fall out of the data shape.
- **`expired` is one closure (`onExpired`):** TT-6's alarm is the only planned consumer, so a single `@MainActor` closure beats a notification or an observer list; TT-5's UI reads the observable state instead.
- **No re-fire on restore of a persisted overtime phase:** the event fired before the quit, so replaying it would re-alarm on every relaunch; only a running phase whose `endDate` passed while quit fires on restore.
- **Expiry scheduling is opt-in (`schedulesExpiry:`):** tests inject a `TestClock` and call `checkExpiry()` by hand, so the wall-clock `Timer` and the `didWakeNotification` observer only arm when the app passes true; `Clock` stays a pure `now` source.
- **Operation edge rules:** `pause` is a no-op unless running (decision 12 shows no pause in overtime), `resume` is a no-op unless paused, `extend` while paused adds to `remaining`, and `start` while paused or in overtime also returns `.needsConfirmation`, because decision 8 states the rule for any active timer.
- **Restore with a missing task:** the state is discarded and the open session is closed with outcome `deleted`, matching the behavior default for deleting the running task.
- **Debug task reuse:** `-debugStartTimerSeconds` reuses an existing open Inbox task named "Debug timer" before creating one, so repeated TT-5/TT-6/TT-7 test launches do not pile up tasks; it is not gated behind `#if DEBUG` because those issues test against the Release build that `make install` produces.
- **Hooks re-entrancy guard:** `done` checks the task through `toggleDone`, and `toggleDone` calls the `taskWasCompleted` hook, so the engine sets a flag while finishing to break the loop.

## Out of scope found

- **Menu bar label is still static** — TT-1's `⏱` item does not show the countdown; TT-5 owns the label and the 1 s refresh.
- **Notification scheduling on engine changes** — the planning doc wants notifications rescheduled on pause, resume, and extend; that is TT-6's `NotificationController`, which will subscribe to this engine.
- **Orphaned open sessions from hard kills** — if the app dies between creating a session and the first state save, one open session row could linger; a sweep for open sessions at launch could be a later hardening issue.
- **`extend` UI amounts (+1m/+5m/+10m/+custom)** — the engine only takes seconds; the button set is TT-5's popover scope.

## Verification

Run in the worktree after the step 0 merge:

- `make gen test lint` — exits 0; the new `TimerEngineTests` and `ActiveTimerStoreTests` suites run and pass.
- The test list must include, by name: switch confirmation changes nothing, replace closes the old session as replaced, pause keeps the remaining time, extend in overtime goes back to running, expired fires exactly once, restore after quit before and after the end, and activeSeconds does not count pauses.
- `git diff origin/master --stat` — only files under `TickTick/Timer/`, `TickTick/Model/`, `TickTick/App/`, `TickTickTests/`, and `docs/` change.
- Manual check (the engine has no UI yet): `make install`, then `open -a TickTick --args -debugStartTimerSeconds 60`, then `defaults read com.jacquesattinger.TickTick` shows the saved active-timer state; quit TickTick, relaunch it plain, read the defaults again to see the restored state, then quit the app and kill every process started.
