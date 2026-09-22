# TT-6: Alarm — screen flash, sound, notification

<!-- Last edited: 2026-09-22 14:28 CDT -->

**TLDR:** When the countdown hits zero, the app must get your attention: every screen flashes white 3 times, the "Glass" sound plays once, and a banner with Done / +5 min / Stop buttons appears in the top right.
This issue builds those three alarm pieces and connects them to the timer engine's "time is up" event.
The flash is gentle on purpose (at most 2 flashes per second, and one slow fade if Reduce Motion is on), and the banner is scheduled with the system ahead of time, so it shows up even if the Mac was asleep when the timer ended.

## Where to find it

The alarm has no menu or window of its own; it appears by itself when a timer reaches zero.
To see it, install the app (`make install`) and start a short timer with the debug launch argument: `open -a TickTick --args -debugStartTimerSeconds 60`.
After 60 seconds the screens flash, the sound plays, and the notification banner shows in the top right of the screen.
The notification permission prompt appears once, on the first launch after this issue lands.

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, the TickTick menu-bar timeboxing app described in `docs/planning.md`.
On `origin/master` today only `README.md` and `docs/` exist: TT-1 (the scaffold), TT-2/TT-3 (model and time code), and TT-4 (the timer engine) are open, plan-stage sibling branches and have not merged.
The planned folder layout gives this issue the `TickTick/Alarm/` folder: `FlashController.swift`, `AlarmSound.swift`, and `NotificationController.swift`.
The alarm layer sits on top of TT-4's `TimerEngine` (`@Observable`, `@MainActor`): the engine fires a single `onExpired` closure exactly once when the timer enters overtime, and it exposes the observable state the alarm needs for scheduling.
Product decision 11 defines the flash and sound, decision 12 the three banner buttons, decision 17 the sleep and wake rule, and decision 18 the Focus behavior; "Technical approach → Notifications / Flash / Sound" fixes the mechanisms.

## What is wrong and why

Nothing is broken; this is a feature gap.
After TT-4 merges, the engine knows the timer expired, but nothing on screen or in the ear tells the user.
The shape of the work, from the issue and the planning doc:

- **Flash:** one borderless `NSWindow` per `NSScreen` at level `.screenSaver`, with `ignoresMouseEvents = true` and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, so it covers full-screen apps and lets clicks pass through.
  White alpha animates 0 → 0.6 → 0 three times in about 1.5 s (2 flashes per second, below the photosensitivity limit of 3 per second).
  With `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` on, it does one slow fade instead.
- **Sound:** `NSSound(named: "Glass")`, played once, in-process, so Focus cannot silence it.
- **Notification:** `UNUserNotificationCenter`, category `TIMER_DONE` with actions Done / +5 min / Stop, title `Time's up: <task>`, body `Estimate was 45 min`, interruption level `.timeSensitive` (fallback `.active` if TT-1 had to drop the entitlement).
  It is scheduled ahead with a time-interval trigger, rescheduled on pause, resume, and extend, cancelled on stop and done, and its actions route to `TimerEngine` (`done`, `extend(seconds: 300)`, `stop`).
- **Wiring:** flash and sound fire on the engine's `onExpired` event, which TT-4 also fires on wake from sleep and on restore-from-quit past the end time.

Two integration facts shape the design.
First, TT-4's plan gives the engine one `stateDidChange` closure, and `ActiveTimerStore` already consumes it; the alarm therefore observes the `@Observable` engine with `withObservationTracking`, the same pattern TT-5's `StatusItemController` uses, and touches no TT-4 file.
Second, `UNUserNotificationCenter` cannot run in plain unit tests (it needs a signed app bundle), so the scheduling rules live in a pure planner type that tests drive with plain values, and a thin protocol lets tests fake the center itself.

## Likely touched files

- `TickTick/Alarm/FlashController.swift` — new; the per-screen overlay windows, the animation runner, and the pure `FlashTimeline` keyframe builder (testable without windows).
- `TickTick/Alarm/AlarmSound.swift` — new; plays "Glass" once and keeps a strong reference while it plays.
- `TickTick/Alarm/NotificationPlanner.swift` — new; pure logic: notification content (title, body) from task name and planned seconds, and the schedule / reschedule / cancel decision for each timer state.
- `TickTick/Alarm/NotificationController.swift` — new; the `UNUserNotificationCenter` wrapper: permission request, `TIMER_DONE` category, delegate for foreground presentation and action routing, and applying the planner's decisions.
- `TickTick/Alarm/AlarmController.swift` — new; the coordinator: hooks `onExpired` for flash + sound, observes engine state changes for notification scheduling, and owns the three pieces above.
- `TickTick/App/AppDelegate.swift` — edited (from TT-1/TT-4/TT-5); builds `AlarmController` at launch, requests notification permission, and sets the notification delegate before launch finishes.
- `TickTickTests/FlashTimelineTests.swift` — new; keyframe counts, alpha bounds, total duration, flash rate, and the Reduce Motion variant.
- `TickTickTests/NotificationPlannerTests.swift` — new; content text and one scheduling decision per timer state.
- `TickTickTests/NotificationControllerTests.swift` — new; reschedule and cancel flows against a fake notification center.
- `docs/alarm-flash-sound-notification_plan.md` — this plan.

## Plan

0. **Sync the branch and gate on TT-4.**
   Run `git fetch` and merge `origin/master` into this branch.
   Confirm the TT-4 code is present (`TickTick/Timer/TimerEngine.swift` with `onExpired`, the observable state, and the `-debugStartTimerSeconds` launch argument) and that `make gen build test lint` passes before any new code.
   If TT-4 (TOD-8) has not merged, stop and report the unmet dependency instead of coding against a guessed API.
   If TT-4's real API differs from the shape assumed here (closure names, state cases, session ID access), adapt to the real API and note the deltas in the PR description.
   Also check `TickTick/Resources/TickTick.entitlements` and the README for TT-1's time-sensitive entitlement outcome, and pick `.timeSensitive` or the `.active` fallback now.
1. **Flash and sound commit.**
   Add `TickTick/Alarm/FlashController.swift`.
   A pure `FlashTimeline` struct builds the keyframes: `standard` gives 3 cycles of alpha 0 → 0.6 → 0 over 1.5 s total (each cycle 0.25 s in, 0.25 s out, so 2 flashes per second), and `reduceMotion` gives one slow fade 0 → 0.6 → 0 over the same 1.5 s.
   The `@MainActor` `FlashController.flash()` method reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, creates one borderless window per current `NSScreen` (white background, `alphaValue = 0`, level `.screenSaver`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `isReleasedWhenClosed = false`), orders them front without activating the app, plays the timeline with chained `NSAnimationContext` groups, and closes and releases every window at the end.
   A second `flash()` while one runs tears the old windows down first, so nothing stacks.
   Add `TickTick/Alarm/AlarmSound.swift`: `play()` creates `NSSound(named: "Glass")`, keeps it in a property until it finishes, and plays it once.
   Add `TickTickTests/FlashTimelineTests.swift`: the standard timeline has exactly 3 peaks, no alpha above 0.6, a total duration of about 1.5 s, and a peak rate of at most 2 per second; the Reduce Motion timeline has exactly 1 peak.
   Commit with its tests.
2. **Notification planner commit.**
   Add `TickTick/Alarm/NotificationPlanner.swift`, all pure values.
   `NotificationContent.make(taskName:plannedSeconds:)` returns title `Time's up: <task>` and body `Estimate was <human duration>` through TT-3's `TimeFormatting.human`.
   `NotificationPlanner.plan(for:now:)` maps a timer state to one decision: running → `.schedule(id: sessionID, fireIn: endDate − now)`, paused → `.cancel(id:)`, overtime → `.ensureDelivered(id:)`, idle → `.cancel(id:)` (stop and done both land here).
   The identifier is the session UUID string, so a reschedule replaces the old request and nothing can fire twice.
   Add `TickTickTests/NotificationPlannerTests.swift`: the content strings, one decision per state, and a zero-or-negative interval in running maps to `.ensureDelivered`.
   Commit with its tests.
3. **Notification controller commit.**
   Add `TickTick/Alarm/NotificationController.swift`.
   A small `UserNotificationCentering` protocol wraps the center calls the controller uses (`requestAuthorization`, `setNotificationCategories`, `add`, `removePendingNotificationRequests`, `deliveredNotifications`), with `UNUserNotificationCenter` conforming and a test fake in the test target.
   At launch the controller registers the `TIMER_DONE` category with actions Done, +5 min, and Stop, sets itself as the center's delegate, and requests authorization for alerts and sounds (the system shows the prompt only on the first launch; a denial is stored and everything else still works).
   `apply(_ decision:)` executes a planner decision: schedule adds a request with a `UNTimeIntervalNotificationTrigger`, the chosen interruption level, and no notification sound; cancel removes the pending request; ensureDelivered checks `deliveredNotifications` for the identifier and adds an immediate request (nil trigger) only when it is absent, which covers wake-from-sleep and restore-from-quit without double banners.
   The delegate routes actions to the engine: Done → `done()`, +5 min → `extend(seconds: 300)`, Stop → `stop()`; every action first checks that the notification's session ID matches the engine's current session, so a stale banner does nothing.
   `willPresent` returns `.banner` so the banner also shows while TickTick is active.
   Add `TickTickTests/NotificationControllerTests.swift` with the fake center: schedule then cancel leaves nothing pending, a reschedule replaces the request under the same identifier, and ensureDelivered adds nothing when the identifier was already delivered.
   Commit with its tests.
4. **Coordinator and app wiring commit.**
   Add `TickTick/Alarm/AlarmController.swift` (`@MainActor`): it owns `FlashController`, `AlarmSound`, and `NotificationController`; it sets `engine.onExpired` to run `flash()` plus `play()` plus the overtime planner decision; and it re-arms `withObservationTracking` on the engine state so every start, pause, resume, extend, stop, and done runs the planner and applies the result.
   Edit `TickTick/App/AppDelegate.swift` minimally (TT-5 edits the same file in parallel): build the `AlarmController` with the shared engine, and let it register the category, set the delegate, and request permission during `applicationDidFinishLaunching`.
   Commit; the coordinator's behavior is covered by the planner and controller tests plus the manual pass.
5. **Manual verification and polish commit.**
   Run the full Verification list below on the installed app and fix what looks or behaves wrong (flash tint, animation stutter, banner text, button order).
   Confirm every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, no file is over 500 lines, and no function is over 75 lines.
   Run `make test lint`, push, and open the PR linked to TOD-10.

## Decisions made alone

- **Hard stop when TT-4 is absent (step 0).**
  Every API this issue consumes (`onExpired`, the observable state, the session ID, the debug launch argument) lives in an unmerged sibling PR; coding against a guess gives an unbuildable branch.
  This is the same call the TT-4 and TT-5 plans made for their dependencies.
- **Two files beyond the planned three (`AlarmController.swift`, `NotificationPlanner.swift`).**
  Sources are globbed, so new files cost nothing (TT-5 set the precedent), the coordinator keeps `AppDelegate` edits minimal while TT-5 rewrites the same file, and a pure planner is the only way to unit-test scheduling rules that `UNUserNotificationCenter` itself makes untestable.
- **State observation via `withObservationTracking`, not the engine's `stateDidChange` closure.**
  TT-4's plan gives that closure to `ActiveTimerStore`; observing the `@Observable` engine needs no TT-4 change and copies TT-5's `StatusItemController` pattern.
  If the merged engine offers a multi-listener hook instead, use it and note the delta.
- **The notification identifier is the session UUID.**
  One stable identifier per timer session means a reschedule replaces instead of adds, a stale action can be detected, and "nothing fires twice" falls out of the design.
- **Pause cancels the pending notification; resume schedules a fresh one.**
  The brief says "reschedule on pause", but a paused timer has no end date to schedule against, and the acceptance criteria say a paused timer never fires the banner; cancel-then-reschedule is the only reading that satisfies both.
- **On `expired`, the notification path is "ensure delivered", not "post again".**
  The time-interval trigger normally fired already; only when the identifier is in neither the delivered nor the pending list (wake races, permission granted late) does an immediate copy go out.
- **The notification itself is silent (no `UNNotificationSound`).**
  `AlarmSound` plays "Glass" in-process on the same event; a notification sound would double it, and Focus could suppress the notification sound but never the in-process one (decision 18).
- **The interruption level is decided in step 0 from TT-1's entitlement outcome.**
  The planning doc names the fallback; reading the entitlements file and README beats guessing.
- **Flash windows are created per flash and closed after.**
  Screens are read at fire time, so display changes between alarms need no observer, and no invisible windows linger.
- **The Reduce Motion fade uses the same 1.5 s total and 0.6 peak alpha as the standard flash.**
  The spec fixes only "one slow fade"; keeping duration and peak identical changes exactly one variable (the peak count) between the two modes.
- **`willPresent` shows the banner while the app is active.**
  A menu bar app is often technically frontmost; without this the banner silently drops exactly when the user is at the Mac.
- **Notification actions are guarded by session ID.**
  A user can stop the timer from the popover while the banner still sits in Notification Center; a stale Done or +5 min must not touch a later timer.
- **Permission is requested on every launch.**
  `requestAuthorization` prompts only once system-wide, so an unconditional call at launch is idempotent and implements "requested on first launch" without extra state.
- **The "permission denied" popover hint is not built here.**
  The planning behavior default puts that hint in the popover, which is TT-5's file and an open parallel PR; it is filed under out of scope instead of creating a cross-PR conflict.

## Out of scope found

- **Popover hint when notification permission is denied** — the planning behavior defaults want the popover to show a hint; the popover is TT-5's parallel scope, so this needs a small follow-up after both merge.
- **Menu bar turns red and counts up in overtime** — decision 12's visual half lives in TT-5's `StatusItemLabel`, not here.
- **Alarm sound picker** — planning lists it under "Later ideas"; the sound stays hard-coded to "Glass" in v1.
- **Displays added mid-flash** — a display plugged in during the 1.5 s animation is not covered until the next alarm; not worth an observer for a 1.5 s window.

## Verification

Run in the worktree after the step 0 merge, on a machine where Jacques has run the `xcode-select` prerequisite.

1. `make gen test lint` — exits 0; `FlashTimelineTests`, `NotificationPlannerTests`, and `NotificationControllerTests` run and pass.
2. `git diff origin/master --stat` — only files under `TickTick/Alarm/`, `TickTick/App/`, `TickTickTests/`, and `docs/` change.
3. `make install`, then `open -a TickTick --args -debugStartTimerSeconds 60` — the first launch shows the notification permission prompt (accept it); at zero, every display flashes white exactly 3 times in about 1.5 s, "Glass" plays once, and the banner shows `Time's up: Debug timer` with Done, +5 min, and Stop.
4. During the flash, click something under the overlay — the click lands (clicks pass through).
5. Banner buttons, one timer each: +5 min returns the timer to running for 5 more minutes; Stop ends it; Done ends it and checks the "Debug timer" task; nothing fires a second banner or a second sound.
6. Start a 60 s timer, pause it from the engine state before zero — no banner fires at the original end time; stop a running timer before zero — same.
7. Put an app in full screen, start a 60 s timer — the flash covers the full-screen app.
8. Turn a Focus mode on, start a 60 s timer — the flash and sound still fire, and the banner appears (time-sensitive), or matches the documented `.active` fallback.
9. Start a 2 min timer, sleep the Mac for about 3 min, wake it — the alarm fires exactly once on wake.
10. System Settings → Accessibility → Display → Reduce Motion on, start a 60 s timer — one slow fade instead of 3 flashes; turn Reduce Motion back off.
11. `codesign -d --entitlements - /Applications/TickTick.app` — matches the interruption-level choice from step 0.
12. Quit TickTick, `pgrep -x TickTick` returns nothing, and no other started process is left.
