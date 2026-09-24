# TT-5: Menu bar item and popover

<!-- Last edited: 2026-09-24 16:44 PT -->

**TLDR:** We give the timer a face.
The `⏱` in the menu bar starts to show the running task and its time, turns red when time is up, and dims when the timer is paused.
A click on it opens a small panel (a popover) with the task details and buttons to pause, extend, stop, or finish the timer.

## Where to find it

Click the `⏱` item in the macOS menu bar at the top right of the screen.
The item itself shows the timer state as text; the click opens the popover with the controls.
To see the active state without the quick-add UI (which TT-7 builds), quit TickTick and start the app with a debug timer: `open build/Build/Products/Debug/TickTick.app --args -debugStartTimerSeconds 60`.

## Orientation

The area is the TickTick macOS menu bar app described in `docs/planning.md`.
TT-1, TT-2, and TT-3 are on `origin/master`.
This branch also merges the code branch of TT-4 (TOD-8, the timer engine, PR #15), so its code is present.
The part this issue owns is the `TickTick/MenuBar/` folder from the planned folder layout: everything the user sees in the menu bar and in the popover.
The exact sections are two planned files: `StatusItemController.swift` (the `NSStatusItem` label per timer state, the 1 s refresh, and the popover toggle) and `TimerPopoverView.swift` (the SwiftUI content of the popover, active and idle).
Product decisions 9 (menu bar text), 10 (popover content and buttons), and 12 (red overtime label that counts up) define the required look, and "Technical approach → Menu bar" mandates AppKit `NSStatusItem` + `NSPopover` hosting SwiftUI instead of SwiftUI `MenuBarExtra`.
TT-1's `AppDelegate` only shows a static `⏱` with a "Quit TickTick" menu; this issue replaces that stub.
The stub stays only as a fallback when the data store cannot open.
The state comes from TT-4's `TimerEngine` (`@Observable`, `@MainActor`, states idle / running / paused / overtime, operations `pause`, `resume`, `extend(seconds:)`, `stop`, `done`), and the text comes from TT-3's `TimeFormatting` (`countdown`, `overtime`, `human`, `clock`, `menuBarName`, plus a new `day`) and `DurationParser`.

## What is wrong and why

Nothing is broken; this is a gap.
After TT-4 merges, a timer can run, but nothing on screen shows it and nothing lets the user control it.
The shape of the fix is:

1. A pure label builder turns a timer state into an `NSAttributedString` (symbol, cut name, time, color, monospaced digits), so the label logic is unit-testable without a real status item.
2. `StatusItemController` owns the `NSStatusItem`, sets the label from the builder, refreshes it every 1 s, and toggles a `.transient` `NSPopover` on click (transient popovers close on an outside click for free).
3. `TimerPopoverView` renders the active state (task facts, progress, time buttons, Pause/Resume, Stop, Done, and an inline "+custom" field that uses `DurationParser`) or the idle state ("No timer running", the ⌃⌥Space hint), with "Quit TickTick" always present.
4. `AppDelegate` drops its TT-1 stub status item and instantiates `StatusItemController` instead.

## Touched files

- `TickTick/MenuBar/StatusItemLabel.swift` — new; pure builder `make(for:taskName:now:) -> NSAttributedString` for the four label states, the monospaced-digit font, and `nextChange(for:after:)` for the refresh timing.
- `TickTick/MenuBar/StatusItemController.swift` — new; owns `NSStatusItem` + `NSPopover`, the 1 s refresh timer, observation of `TimerEngine`, and the click toggle.
  It also holds `PopoverClock`, the time the popover shows.
- `TickTick/MenuBar/TimerPopoverView.swift` — new; SwiftUI popover content, active and idle states, the action buttons, and the footer.
- `TickTick/MenuBar/ExtendControls.swift` — new; the `+1m +5m +10m +custom` row and the inline custom field (`CustomExtendEntry`).
- `TickTick/MenuBar/TimerPopoverModel.swift` — new; the popover's derived display values.
- `TickTick/Time/TimeFormatting.swift` — adds `day(_:)` (`Thu 24 Sep`).
- `TickTick/App/AppDelegate.swift` — replaces the TT-1 stub status item with `StatusItemController`.
- `TickTickTests/StatusItemLabelTests.swift`, `TimerPopoverModelTests.swift`, `CustomExtendEntryTests.swift` — new.
  `TimeFormattingTests.swift` and `ScaffoldTests.swift` — updated.
- `docs/menu-bar-item-and-popover_plan.md` — this plan.

## Plan

0. **Sync the branch.**
   Run `git fetch` and merge `origin/master` into this branch.
   Confirm the TT-4 code is present (`TickTick/Timer/TimerEngine.swift`, the `-debugStartTimerSeconds` launch argument) and that `make gen build test lint` passes before any new code.
   TT-4 (TOD-8) is still in PR #15, so this branch merges its code branch `jacques/tod-8-tt-4-timer-engine-code`.
   If TT-4's real API differs from the shape assumed here (names, event delivery), adapt to the real API and note the deltas in the PR description.
1. **Label builder commit.**
   Add `TickTick/MenuBar/StatusItemLabel.swift`: a caseless `enum StatusItemLabel` with `static func make(for state: ...) -> NSAttributedString`, taking the engine state plus the task name and remaining/overtime seconds.
   Output per state (decision 9 and 12):
   - Idle: `⏱` only.
   - Running: `⏱ <name> · 24:13` in the standard label color.
   - Paused: `⏸ <name> · 24:13` in `.secondaryLabelColor` (dimmed).
   - Overtime: `⏱ <name> · +2:13` in `.systemRed`.
   The name goes through `TimeFormatting.menuBarName` (24-character cut), the time through `TimeFormatting.countdown` / `.overtime`, and the whole string uses `NSFont.monospacedDigitSystemFont` so the width does not jump while counting.
   Add `TickTickTests/StatusItemLabelTests.swift`: one case per state asserting the string, the color attribute, and the font; plus a long-name case asserting the `…` cut.
2. **Status item and popover shell commit.**
   Add `TickTick/MenuBar/StatusItemController.swift` (`@MainActor` final class):
   - Creates the `NSStatusItem` with `variableLength`, sets `button.attributedTitle` from `StatusItemLabel`, and sets the click action to toggle the popover.
   - Owns an `NSPopover` with `behavior = .transient` and an `NSHostingController(rootView: TimerPopoverView(...))`; `toggle()` shows it relative to the status button or closes it.
   - Refreshes the label every 1 s with a main-run-loop `Timer` added in `.common` mode, and also re-renders immediately on any engine state change via Observation (`withObservationTracking` re-armed on each change), so Pause and Resume update the label without waiting for the next tick.
   Rewrite `TickTick/App/AppDelegate.swift`: remove the TT-1 stub `NSStatusItem` and its menu, and instantiate `StatusItemController` with the shared `TimerEngine`.
   The "Quit TickTick" menu item from TT-1 is deleted here; its replacement is the popover button in step 3, so both land before the PR opens.
3. **Popover content commit.**
   Add `TickTick/MenuBar/TimerPopoverView.swift` with a fixed content width of about 300 pt and two states switched on the engine state:
   - Active (running / paused / overtime), per decision 10: task name (headline), note name line with a disabled placeholder area for "Open ↗" (TT-8), the time left large and centered (`TimeFormatting.countdown`, or red `+m:ss` in overtime), a `ProgressView` bar with a percent label, the line `Started 2:57 PM · Ends 3:42 PM` (`TimeFormatting.clock`), and the line `Estimate 45m · Tue 22 Sep`.
   - Buttons: a row `+1m  +5m  +10m  +custom` calling `engine.extend(seconds:)`, then `Pause`/`Resume` (state-dependent), `Stop`, and `Done` (prominent).
   - "+custom" flips an inline `TextField` into the row; input goes through `DurationParser.parse`, Return extends, Esc or an outside click cancels, and an unparseable value disables the confirm and shows the field in an error tint.
   - Idle: "No timer running", the dimmed hint "New task: ⌃⌥Space", and a disabled placeholder area for "Open Notes" (TT-8) and "Settings…" (TT-11).
   - A footer with "Quit TickTick" (`NSApplication.terminate`) in both states, because the app usually has no Dock icon.
   Extract the derived display values into a small pure struct `TimerPopoverModel` in its own file (progress fraction clamped to 0…1, percent text, started/ends text, estimate/date text), and add `TickTickTests/TimerPopoverModelTests.swift` with a fixed locale, time zone, and `now`.
   All time text uses monospaced digits so nothing shifts while counting.
4. **Manual verification and polish commit.**
   Run the full Verification list below on the installed app and fix what looks wrong: spacing, truncation, dark-mode colors, popover arrow position, and label width jitter.
   Fold small fixes into this commit; anything larger goes back into the file it belongs to.

## Decisions made alone

- **A third file, `StatusItemLabel.swift`, splits the label logic out of `StatusItemController.swift`.**
  Reason: the planning folder layout names only two MenuBar files, but sources are globbed so a new file costs nothing, and a pure builder is the only way to unit-test the label (color, cut, font) without driving a real status item.
- **The paused label keeps the `⏸` symbol and dims via `.secondaryLabelColor`,** not via alpha or `appearsDisabled`.
  Reason: decision 9 says "dimmed" without a mechanism; the secondary label color adapts to light and dark mode by itself.
- **The overtime symbol stays `⏱`** (red `⏱ name · +2:13`), not `⏸` or another symbol.
  Reason: the issue's own scope line shows `⏱` for overtime.
- **Popover close on outside click uses `NSPopover.behavior = .transient`.**
  Reason: that is the platform mechanism for exactly this; no event monitor is needed.
- **While paused, the "Ends" time shows the projected end (`now + remaining`), refreshed with the 1 s tick.**
  Reason: the spec does not cover paused "Ends"; a projected end stays truthful (it is when the timer would end if resumed now), while a frozen stale time would be wrong the moment you pause.
- **Progress = elapsed ÷ planned total including extensions, clamped to 100 % in overtime.**
  Reason: decision 10 shows one bar plus a percent; extensions grow the planned total in TT-4's engine, and a bar over 100 % has no visual meaning.
- **The date in the estimate line is the timer's start date, formatted `EEE d MMM` (`Tue 22 Sep`).**
  Reason: the mockup text shows that shape; the start date is the only date the session owns.
- **"Estimate 45m" uses `TimeFormatting.human` with its spacing (`45 min`), not a new `45m` formatter.**
  Reason: the reuse rule beats matching the mockup's abbreviation letter-for-letter; if Jacques wants `45m`, it is a one-line change in review.
- **Placeholders for TT-8 and TT-11 are real, disabled controls (hidden-from-click, visible slots), not comments.**
  Reason: the issue says "leave clear places"; a disabled slot keeps the layout stable so TT-8/TT-11 do not reflow the popover.
- **"Quit TickTick" appears in both popover states,** although the issue lists it only under idle.
  Reason: the planning "Behavior defaults" section says the popover always has Quit, and that section outranks the shorter issue summary.
- **The 1 s refresh is a plain `Timer` in `.common` run-loop mode plus Observation for instant state-change updates.**
  Reason: a 1 s cadence is what the issue asks for; `.common` mode keeps it ticking during event tracking, and Observation removes the up-to-1-s lag after a button press.
- **No new keyboard shortcuts in the popover.**
  Reason: Space / D / S / 1 / 5 / 0 are explicitly TT-11's scope.
- **Step 0 merges `origin/master` and the TT-4 code branch.**
  Reason: TT-4 is still in PR #15; the named APIs (`TimerEngine`, the debug launch argument) exist only there.

### Decisions made during the work

- **`Open Notes` and `Settings…` sit in the footer of both popover states, next to Quit,** not only in the idle state.
  Reason: you want Settings while a timer runs too, and one footer keeps the layout the same in both states.
- **The popover model and the extend row are in their own files** (`TimerPopoverModel.swift`, `ExtendControls.swift`).
  Reason: small files are easier to test and read; sources are globbed.
- **The refresh fires just after each shown second changes** (`StatusItemLabel.nextChange`), not at a random phase.
  Reason: a free-running 1 s timer can show a second up to 1 s late.
  The popover time comes from the same tick (`PopoverClock`), so the label and the popover always agree.
- **The paused symbol gets extra space after it, so `⏸` takes the same width as `⏱`.**
  Reason: `⏸` is 2 pt narrower, so a pause moved the item and the popover arrow.
- **The popover shows a caption above the big time (`Time left`, `Paused`, `Over time`), dims the time and the bar while paused, and says `Ended` in overtime.**
  Reason: the state must be clear without the menu bar; `Ends 3:25 PM` is wrong once that time is past.
- **Pause is disabled in overtime.**
  Reason: the engine cannot pause in overtime; decision 12 ends overtime with Done, an extension, or Stop.
- **The buttons share the row width; `+custom` keeps its own width.**
  Reason: four equal buttons cut `+custom` to `+cust…` at 300 pt.
- **When the data store cannot open, the app keeps the TT-1 `⏱` item with a Quit menu.**
  Reason: without it, a store error leaves an app with no UI that you cannot quit.
- **The popover closes and reopens on the current Space when you click the item after a Space change.**
  Reason: a popover left open on another Space made the next click only close it, out of sight.
- **A click on the item activates the app with `NSApp.activate(ignoringOtherApps:)`; an accessibility press does not.**
  Reason: the `+custom` field needs key presses, so the app must be active.
  macOS refused the newer `activate()` for a status item click in the E2E test, and the older call worked in a normal Space and over a full-screen app.
  An activation without a click made the transient popover close at once, so an accessibility press opens the popover without it (the buttons still work).
- **The `+custom` field takes focus 50 ms after it appears.**
  Reason: focus set in `onAppear` or at once in `.task` was lost; the field was not yet in the window.

## Out of scope found

- **TT-1 stub status item has no popover** — expected; this issue replaces it, nothing to file.
- **Right-click on the status item does nothing** — a right-click menu (for example Quit) is a common menu bar convention; not in any decision, possible polish for TT-13.
- **Global ⌃⌥T popover toggle** — the reason `NSStatusItem` was chosen over `MenuBarExtra`; TT-11 owns it.
  Found in E2E: over a full-screen app the menu bar is hidden, and a popover opened without a click (as a hotkey would) can appear off screen, next to the hidden item.
  TT-11 must test that case.
- **Overtime tint for the whole popover time display beyond the label** — done here after all: in overtime the popover time and the bar are red too, to match the label.

## Verification

1. `make gen test lint` — exits 0; `StatusItemLabelTests` and `TimerPopoverModelTests` pass.
2. `make build`, quit TickTick, then `open build/Build/Products/Debug/TickTick.app --args -debugStartTimerSeconds 60` — the label shows `⏱ Debug timer · 0:5x` counting down with no width jitter.
3. Drive every state from the popover: Pause (label `⏸`, dimmed, frozen) → Resume → `+5m` → wait past zero (label red `+0:0x` counting up) → `+1m` (back to running) → `+custom` with `2m` → Done (timer ends, task checked).
4. Relaunch with the debug argument and verify Stop as the second ending path, and that the idle popover then shows "No timer running", the ⌃⌥Space hint, and Quit.
5. Long-name check: rename the debug task in code or start one with a name over 24 characters and confirm the `…` cut in the label.
6. A click outside the popover closes it; a second click on the status item also closes it.
7. Repeat the visual pass in light mode and dark mode, on the notched built-in display and on an external display: no clipped text, correct colors.
8. Quit TickTick via the popover button, then `pgrep -x TickTick` to confirm nothing is left running.
