# TT-4: Timer engine

<!-- Last edited: 2026-09-24 15:26 PT -->

**TLDR:** We build the app's "brain" for the one countdown timer: a small state machine that knows if a timer is idle, running, paused, or past zero (overtime).
It writes its state to disk on every change, so the timer survives a quit, a crash, or the Mac going to sleep.
There is no UI in this issue — fake-clock unit tests prove every rule, and a hidden launch argument lets the next three issues start a timer before the real "add task" UI exists.

## Where to find it

Not UI-reachable.
This issue is the timer logic layer: pure state code under `TickTick/Timer/`, plus small hooks in `TaskService` and the app startup in `TickTick/App/`.
TT-5 (menu bar and popover), TT-6 (alarm), and TT-7 (quick-add) put this engine on screen later.
The only way to poke it today is the launch argument `open build/Build/Products/Debug/TickTick.app --args -debugStartTimerSeconds 60`, which starts a 60-second timer on an Inbox task named "Debug timer".
Quit TickTick first, because `open` ignores the arguments when the app already runs.
The engine writes one log line per change: `log show --last 5m --predicate 'subsystem == "com.jacquesattinger.TickTick"'`.

## Orientation

The repo is `JacquesAttinger/TickTick`, the TickTick menu-bar timeboxing app described in `docs/planning.md`.
TT-1 (TOD-5, the Xcode scaffold) is on `origin/master`.
This branch merges the code branches of TT-2 (TOD-6, the SwiftData model and `TaskService`, PR #14) and TT-3 (TOD-7, the duration parser and time formatting, PR #13), so their code is present.
The planned folder layout gives this issue the `TickTick/Timer/` folder: `Clock.swift`, `TimerState.swift`, `TimerEngine.swift`, and `ActiveTimerStore.swift`.
The engine sits between the data layer (`TickTick/Model/TaskService.swift`, from TT-2) and the future UI: it owns the one active timer, records `TimerSession` rows through `TaskService`, and tells listeners when the timer expires.
Product decision 8 gives the one-timer switch rule, decision 10 the operations the popover needs, decision 12 the overtime behavior, decision 17 the sleep and relaunch rules, and "Behavior defaults" the check and delete rules for the running task.

## What is wrong and why

Nothing is broken; this is a feature gap.
No timer logic exists, and three parallel issues (TT-5, TT-6, TT-7) all need a working engine to build on.
The shape of the work, from `docs/planning.md` ("Technical approach → Timer engine") and the issue:

- A clock protocol (`TimerClock`) with a system clock and a hand-advanced test clock, so every rule is testable without waiting.
- A `TimerState` value type: `idle`, or an active timer that is `running(endDate)`, `paused(remaining)`, or `overtime(since)`, plus the task ID, planned seconds, and `startedAt`.
  It stores `endDate` or `remaining`, never a tick counter, so sleep and relaunch cannot make it drift.
- A `TimerEngine` (`@Observable`, `@MainActor`) with `start`, `pause`, `resume`, `extend`, `stop`, and `done`, the switch-confirmation rule, `TimerSession` bookkeeping through `TaskService`, and an `expired` event that fires exactly once when the timer enters overtime.
- An `ActiveTimerStore` that saves the state to `UserDefaults` on every change and restores it on launch, going straight to overtime (and firing `expired`) when the end passed while the app was quit.
- A re-check on `NSWorkspace.didWakeNotification`, hooks so that checking or deleting the running task acts like `done` or a delete-flavored `stop`, and the `-debugStartTimerSeconds` launch argument.

One gap in the dependency: TT-2's `TaskService` ships only note and task primitives and leaves session handling to TT-4.
So this issue also adds the session operations (`startSession`, `closeSession`, fetch by ID) to `TaskService`.

## Likely touched files

- `TickTick/Timer/Clock.swift` — new; `TimerClock` protocol (`var now: Date`) and `SystemClock`.
- `TickTick/Timer/TimerState.swift` — new; Codable `TimerState` (`.idle` / `.active(ActiveTimer)`) and the `ActiveTimer` struct with phase, task ID, session ID, planned seconds, `startedAt`, the active-seconds fields, and `remaining(at:)`, `overtime(at:)`, `activeSeconds(at:)`, and `endDate(at:)`.
- `TickTick/Timer/TimerEngine.swift` — new; the `@Observable @MainActor` state machine with all operations, the switch rule, session bookkeeping, restore, the wake re-check, and the single `onExpired` call.
- `TickTick/Timer/ActiveTimerStore.swift` — new; `UserDefaults` save on every change and restore on launch.
- `TickTick/Model/TaskService.swift` — edited (from TT-2); adds `startSession`, `closeSession`, `session(withID:)`, `task(withID:)`, `setEstimate(_:for:)`, and the `TaskTimerHooks` protocol behind the `timerHooks` property.
- `TickTick/App/AppCore.swift` — new; builds and holds the `ModelStore`, `TaskService`, `TimerEngine`, and `ActiveTimerStore`, and runs the launch order.
- `TickTick/App/DebugTimerLaunch.swift` — new; reads `-debugStartTimerSeconds N` and starts the debug timer.
- `TickTick/App/AppDelegate.swift` — edited (from TT-1); builds `AppCore` at launch (not in the test host) and restores the timer.
- `TickTickTests/TestClock.swift`, `TickTickTests/TestTimerDefaults.swift` — new; the hand-moved clock and a per-test saved-timer key.
- `TickTickTests/TimerStateTests.swift`, `TaskServiceSessionTests.swift`, `TimerEngineTests.swift`, `TimerEngineExpiryTests.swift`, `ActiveTimerStoreTests.swift`, `AppCoreTests.swift` — new tests.
- `docs/timer-engine_plan.md` — this plan.

## Plan

0. Sync the branch: `git fetch`, then merge `origin/master` (TT-1) and the TT-2 and TT-3 code branches, so the scaffold, the model layer, and the time code are present.
1. Add `TickTick/Timer/Clock.swift` and `TickTick/Timer/TimerState.swift`.
   `TimerClock` exposes `var now: Date`; `SystemClock` returns `.now`; `TestClock` (in the test target) starts at a fixed date and has `advance(by seconds:)`.
   `TimerState` is `.idle` or `.active(ActiveTimer)`.
   `ActiveTimer` is Codable and holds `taskID: UUID`, `sessionID: UUID`, `plannedSeconds: TimeInterval`, `startedAt: Date`, `accumulatedActiveSeconds: TimeInterval`, `lastResumedAt: Date?` (nil while paused), and `phase: Phase` with `running(endDate: Date)`, `paused(remaining: TimeInterval)`, and `overtime(since: Date)`.
   Add Codable round-trip tests for every phase.
   Commit with its tests.
2. Add the session operations to `TickTick/Model/TaskService.swift`: `startSession(for:plannedSeconds:at:) -> TimerSession`, `closeSession(_:endedAt:activeSeconds:plannedSeconds:outcome:)`, `session(withID:)`, `task(withID:)`, and `setEstimate(_:for:)`.
   Add their tests to `TickTickTests/TaskServiceSessionTests.swift`, including "a closed session shows up in `actualSeconds(for:)`".
   Commit with its tests.
3. Add `TickTick/Timer/TimerEngine.swift` with the core transitions and session bookkeeping.
   `start(task:seconds:replacing:)` returns `.started` or `.needsConfirmation(current:)` and changes nothing on confirmation; with `replacing: true` it closes the old session as `replaced` first.
   `pause` (running only) stores `remaining` and folds the run time into `accumulatedActiveSeconds`; `resume` (paused only) sets `endDate = now + remaining`; `stop` closes the session as `stopped`; `done` closes it as `done` and checks the task through `TaskService`.
   Every mutation notifies a `stateDidChange` closure that `ActiveTimerStore` plugs into later.
   Add `TickTickTests/TimerEngineTests.swift` with a `TestClock` and an in-memory `ModelStore`: start, switch confirmation changes nothing, replace closes the old session as `replaced`, pause keeps the remaining time, resume, stop, and done checks the task.
   Commit with its tests.
4. Add expiry and overtime to the engine.
   `checkExpiry()` moves running past `endDate` to `overtime(since: endDate)` and fires the `onExpired` closure; the phase change itself guarantees the event fires only once.
   `extend(seconds:)` while running adds to `endDate`, while paused adds to `remaining`, and in overtime returns to `running(endDate: now + seconds)`; the overtime so far stays in the active time.
   Each extend also grows `plannedSeconds`, so `activeSeconds + remaining == plannedSeconds` until the next overtime.
   When built with `schedulesExpiry: true` (the app; tests pass false) the engine arms one wall-clock `Timer` for `endDate` and re-arms it on every state change, and it re-checks on `NSWorkspace.didWakeNotification`.
   Add `TickTickTests/TimerEngineExpiryTests.swift`: extend while running, extend in overtime goes back to running, `expired` fires exactly once even when `checkExpiry()` runs twice, and `activeSeconds` counts running and overtime but not pauses (run 60 s, pause 30 s, resume 60 s, stop → 120 s).
   Commit with its tests.
5. Add `TickTick/Timer/ActiveTimerStore.swift` and the `TaskService` hooks.
   The store JSON-encodes `TimerState` into an injected `UserDefaults` on every `stateDidChange`, and `restore(into:)` reloads it at launch: a future `endDate` resumes running, a past one goes straight to overtime and fires `expired`, a persisted overtime phase does not fire again, and a missing task clears the state and closes the open session as `deleted`.
   `TaskService` gets a `timerHooks` property of type `TaskTimerHooks` (`taskWasCompleted`, `taskWillBeDeleted`) that `toggleDone`, `deleteTask`, and `deleteNote` call; the engine sets itself there, so checking the running task runs `done` and deleting it closes the session with outcome `deleted`.
   Add `TickTickTests/ActiveTimerStoreTests.swift` (round-trip before the end, restore after the end fires `expired` once, restore of paused and overtime states, missing task) and the hook tests in `TimerEngineTests.swift`.
   Commit with its tests.
6. Wire the app: `AppDelegate` builds `AppCore` (`ModelStore`, `TaskService`, `TimerEngine`, `ActiveTimerStore`) at launch, restores the saved state, and then handles `-debugStartTimerSeconds N` (read from the `UserDefaults` argument domain only): reuse an open Inbox task named "Debug timer" or create one, set its estimate, and start an N-second timer with `replacing: true`.
   The test host skips all of this, so `make test` never opens the real store or restores the saved timer.
   Commit, then run the finishing pass: every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file over 500 lines and no function over 75 lines, `make test lint` green, push, and open the PR linked to TOD-8.

## Decisions made alone

- **Dependencies:** TT-1 is on `master`, and the branch merges the TT-2 and TT-3 code branches, so this code builds on their real APIs.
- **`TimerClock`, not `Clock`:** the protocol does not hide Swift's own `Clock`, the same reason TT-2 named its model `TaskItem`.
  `TestClock` lives in the test target, so the app does not ship it.
- **Session operations live in `TaskService`:** the issue says sessions are created and closed "through `TaskService`", and TT-2's plan explicitly left them out, so this issue adds them there instead of adding a second service.
- **State shape:** one Codable `ActiveTimer` struct with a nested `Phase` enum, instead of a flat four-case enum, because the task ID, session ID, planned seconds, and `startedAt` are common to all three active phases and `Codable` on a struct is simpler to persist.
- **Persisting `sessionID`:** the open `TimerSession` row's ID is part of the saved state, so after a quit or crash the engine can close the same row instead of leaking an open one.
- **Active-seconds bookkeeping:** the state stores `accumulatedActiveSeconds` plus `lastResumedAt`; active time is the sum plus `now - lastResumedAt` while running or in overtime, and `lastResumedAt` is nil while paused, which makes "pauses do not count" fall out of the data shape.
- **`expired` is one closure (`onExpired`):** TT-6's alarm is the only planned consumer, so a single `@MainActor` closure beats a notification or an observer list; TT-5's UI reads the observable state instead.
- **No re-fire on restore of a persisted overtime phase:** the event fired before the quit, so replaying it would re-alarm on every relaunch; only a running phase whose `endDate` passed while quit fires on restore.
- **Expiry scheduling is opt-in (`schedulesExpiry:`):** tests inject a `TestClock` and call `checkExpiry()` by hand, so the wall-clock `Timer` and the `didWakeNotification` observer only arm when the app passes true; `TimerClock` stays a pure `now` source.
- **Operation edge rules:** `pause` is a no-op unless running (decision 12 shows no pause in overtime), `resume` is a no-op unless paused, `extend` while paused adds to `remaining`, and `start` while paused or in overtime also returns `.needsConfirmation`, because decision 8 states the rule for any active timer.
- **Restore with a missing task:** the state is discarded and the open session is closed with outcome `deleted`, matching the behavior default for deleting the running task.
- **Debug task reuse:** `-debugStartTimerSeconds` reuses an existing open Inbox task named "Debug timer" before creating one, so repeated TT-5/TT-6/TT-7 test launches do not pile up tasks; it is not gated behind `#if DEBUG` because those issues test against the Release build that `make install` produces.
- **Hooks re-entrancy (changed during implementation):** `done` closes the session and goes idle before it checks the task through `toggleDone`, so the `taskWasCompleted` hook finds no running task and does nothing.
  No flag is needed.
- **Planned time grows with extend:** `ActiveTimer.plannedSeconds` and the closed session's `plannedSeconds` include every extension, so TT-5's progress bar is `activeSeconds / plannedSeconds`.
- **Deleting a note:** `deleteNote` calls `taskWillBeDeleted` for each of its tasks, so deleting the note of the running task also stops the timer with outcome `deleted`.
- **`AppCore` composition root:** `AppDelegate` keeps one `AppCore`.
  Later steps connect their listeners between `AppCore.init` and `startTimer(launchArguments:)`, so they see the restored state and an expiry on restore.
- **Test host guard:** the unit tests run inside the app, so `AppDelegate` skips `AppCore` when `XCTestConfigurationFilePath` is set.
- **Saved state is JSON text:** `defaults read com.jacquesattinger.TickTick activeTimer` shows it.
  Dates are seconds since 2001-01-01.

## Out of scope found

- **Menu bar label is still static** — TT-1's `⏱` item does not show the countdown; TT-5 owns the label and the 1 s refresh.
- **Notification scheduling on engine changes** — the planning doc wants notifications rescheduled on pause, resume, and extend; that is TT-6's `NotificationController`, which will subscribe to this engine.
- **Orphaned open sessions from hard kills** — if the app dies between creating a session and the first state save, one open session row could linger; a sweep for open sessions at launch could be a later hardening issue.
- **`extend` UI amounts (+1m/+5m/+10m/+custom)** — the engine only takes seconds; the button set is TT-5's popover scope.

## Verification

Run in the worktree after the step 0 merge:

- `make gen test lint` — exits 0; the new `TimerEngineTests`, `TimerEngineExpiryTests`, `ActiveTimerStoreTests`, and `AppCoreTests` suites run and pass.
- The test list must include, by name: switch confirmation changes nothing, replace closes the old session as replaced, pause keeps the remaining time, extend in overtime goes back to running, expired fires exactly once, restore after quit before and after the end, and activeSeconds does not count pauses.
- `git diff origin/master --stat` — only files under `TickTick/Timer/`, `TickTick/Model/`, `TickTick/App/`, `TickTickTests/`, and `docs/` change.
- Manual check (the engine has no UI yet): `make build`, then `open build/Build/Products/Debug/TickTick.app --args -debugStartTimerSeconds 60`, then `defaults read com.jacquesattinger.TickTick activeTimer` shows the saved active-timer state and the engine log shows `start`, then `expired` after 60 s; quit TickTick, relaunch it plain, read the defaults and the log again to see the restored state, then quit the app and kill every process started.
