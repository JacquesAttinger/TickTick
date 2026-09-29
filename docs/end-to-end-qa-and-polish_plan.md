# TT-13: End-to-end QA and polish pass

<!-- Last edited: 2026-09-29 18:20 CDT -->

**TLDR:** All the app's features are built, so now we install the app and test every feature from the full checklist, like a real user would.
Every bug or ugly spot we find gets fixed in this branch, and anything too big to fix here gets written down as a follow-up issue.
The old blocker is gone: the Help tab (TT-12) merged to `master` in PR #27, so the first step is to merge the fresh `master` into this branch and then run the whole checklist.

## Where to find it

This issue covers the whole app, not one feature.
The entry points are: the `⏱` item in the menu bar, the ⌃⌥Space quick-add panel, the popover (click the menu bar item or press ⌃⌥T), the Notes window ("Open Notes" in the popover), and the Settings window ("Settings…" in the popover or ⌘,).
The checklist itself lives in `docs/planning.md` under "Verification (full E2E checklist for TT-13, and a partial one for each step)".

## Orientation

The repo builds one macOS app with XcodeGen (`project.yml`), a `Makefile`, and a SwiftLint/SwiftFormat pre-commit hook.
The app code is split by area under `TickTick/`: `App/` (lifecycle and Dock policy), `Model/` (SwiftData store and `TaskService`), `Time/` (parser and formatters), `Timer/` (engine and persistence), `MenuBar/` (status item and popover), `Alarm/` (flash, sound, notification), `QuickAdd/` (global hotkey panel), `Notes/` (notes window and task rows), and `Settings/` (preferences, hotkeys, shortcut catalog).
All pure logic has Swift Testing tests in `TickTickTests/`, and all UI is verified by hand.
This issue is the final pass: it does not add a feature, it exercises every area on the installed app and fixes what the earlier per-issue Verify steps missed.

## What is wrong and why

Nothing is known to be broken yet; the gap is that no one has run the full 14-item checklist on one installed build that contains every merged step.
Each earlier issue verified its own slice, so cross-feature defects (dark mode on the external display, sleep during overtime, Focus mode, hybrid Dock after many open/close cycles, spacing between components built by different agents) can still hide.
The fix is to run the checklist end to end, commit one focused fix per defect found, and file follow-up issues for anything too large.
The Help-tab gap that stopped the first implementation run is closed: TOD-15 merged to `master` in PR #27, and `TickTick/Settings/HelpView.swift`, `TickTick/Settings/HelpContent.swift`, and `TickTickTests/HelpContentTests.swift` now exist on `origin/master`.
This branch was cut before that merge and now sits 13 commits behind `origin/master`, so the first step is to merge the fresh `master` tip (`f37535d`) into this branch before any checklist run.
The README acceptance criterion is already met: PRs #24 and #25 gave `README.md` a feature list and three screenshots in `images/`, so the README work here is only to re-check it and refresh screenshots if a polish fix changes the visible UI.

## Likely touched files

- `docs/end-to-end-qa-and-polish_plan.md` — this plan.
- `TickTick/MenuBar/*.swift` — likely home of label, popover layout, and dark-mode defects.
- `TickTick/Notes/*.swift` — likely home of row spacing, badge, reorder, and focus-ring defects.
- `TickTick/QuickAdd/*.swift` — likely home of panel focus and layout defects.
- `TickTick/Alarm/*.swift` — likely home of flash, sound, and notification timing defects.
- `TickTick/Timer/*.swift` — likely home of sleep, wake, and relaunch-restore defects.
- `TickTick/Settings/*.swift` — likely home of toggle and hotkey-recorder defects.
- `TickTickTests/*.swift` — a test for every logic fix that a defect forces.
- `README.md` and `images/*.png` — only if a polish fix changes the visible UI shown in the screenshots.

The exact fix files depend on what the checklist finds, so the paths above are the areas each checklist item exercises, not a promise that each one changes.

## Plan

1. `git fetch origin`, confirm `origin/master` contains PR #27 (TOD-15, Help tab; `TickTick/Settings/HelpView.swift` exists), then merge `origin/master` into this branch with a normal merge commit.
   Do not rebase: the branch is already pushed and draft PR #26 tracks it, and a rebase would need a force-push.
   Push the merge, and keep working on draft PR #26 instead of opening a second PR.
2. Run checklist item 1: from a clean state, `scripts/setup.sh && make gen test lint install`, then confirm `⏱` in the menu bar and no Dock icon.
   Commit any tooling fix this surfaces.
3. Launch the installed app against a throwaway store (`-debugStorePath /tmp/ticktick-test/TickTick.store`) and run items 2–5: quick-add, countdown label, popover fields, +1m, pause and resume, the 3-flash alarm with the Glass sound and banner, red overtime count-up, banner "+5 min", and popover Done checking the task in Inbox.
   Commit one focused fix per defect, each with a test when the fix is in pure logic.
4. Run items 6–7: Notes window (new note, 3 tasks, confirm flow, switch prompt, reorder, check and uncheck in place, est/actual badges) and the hybrid Dock icon on close.
   Commit fixes the same way.
5. Run items 8–11: sleep 3 minutes during a 2-minute timer, quit and relaunch with a running timer, alarm under Focus, and flash over a full-screen app.
   Commit fixes the same way.
6. Run items 12–13: every Settings toggle, a rebound hotkey, launch at login, the Help tab contents, then a light-mode and dark-mode sweep on the built-in and an external display.
   Commit fixes the same way.
7. Re-check the README against the acceptance criteria and retake any screenshot in `images/` that a fix changed; otherwise leave the README as merged in PRs #24 and #25.
8. Final gate: `make test lint` green, list every defect that was too big to fix (for follow-up issues) in the PR description, quit TickTick, and kill every process the run started.

## Decisions made alone

- **Treat the README criterion as already satisfied.** PRs #24 and #25 added a feature list and three screenshots, so step 7 verifies instead of rewrites; the reason is to avoid redoing merged work the issue text predates.
- **Merge `master` in, do not rebase onto it.** The branch is pushed and draft PR #26 already tracks it, so a merge commit brings in the Help tab (PR #27) without a force-push; the never-force-push rule decides this.
- **Reuse draft PR #26.** The first implementation run opened it before stopping on the blocker, so all further commits go to the same branch and PR instead of a new one.
- **Use a throwaway store for every manual run.** `-debugStorePath /tmp/ticktick-test/TickTick.store` keeps Jacques's real tasks out of the QA data, per `docs/planning.md`.
- **Sleep test method.** Run item 8 with `pmset sleepnow` after scheduling a wake (`sudo pmset schedule wake ...`); if `sudo` is not available to the agent, mark item 8 as "needs a hand check by Jacques" in the PR description rather than skip it silently.
- **One commit per defect.** Small, focused commits keep the pre-commit hook fast and make a partial revert possible if one fix is wrong.
- **Follow-up filing.** The implement agent cannot write to Linear, so defects too big for this PR are listed in the PR description for Marshall to file and link, which satisfies the issue's "file a new issue and link it here" rule through the orchestrator.
- **External display.** If no external display is attached during the run, note item 13's external-display half as "needs a hand check by Jacques" in the PR description instead of claiming it passed.

## Out of scope found

- **No automated UI test layer** — every UI behavior is verified by hand on each pass; an XCUITest smoke suite would make future QA passes cheaper. Filed as a follow-up later; not fixed here.
- **Alarm sound is fixed to "Glass"** — already recorded as a v1 decision in `docs/planning.md`; a sound picker stays a later idea.

## Verification

Run the full 14-item checklist from `docs/planning.md` on the installed app:

1. `scripts/setup.sh && make gen test lint install` succeeds from clean; `⏱` shows and no Dock icon shows.
2. ⌃⌥Space → "Write cover letter" → Return → `1` → Return → the label counts down from `0:59`.
3. Popover fields are correct; +1m, Pause (`⏸`, frozen), Resume all work.
4. At zero: 3 flashes on every display, the Glass sound, a banner, and a red `+0:0x` count-up.
5. Banner "+5 min" resumes; after the next expiry, popover Done checks the task in Inbox.
6. Notes: new note, 3 tasks, confirm flow, switch prompt, reorder, check and uncheck in place, est/actual badges.
7. Closing Notes removes the Dock icon.
8. Sleep 3 minutes during a 2-minute timer → one alarm on wake and about `+1:00` overtime.
9. Quit and relaunch with a running timer → the timer restores correctly.
10. With Focus on, the flash and sound still fire.
11. The flash covers a full-screen app.
12. Every Settings toggle works, a rebound hotkey works, launch at login works, and Help lists every feature and shortcut.
13. Light and dark mode on the built-in and an external display show no clipped or misaligned UI.
14. `make test lint` is green, and every process started for QA is killed before reporting done.

Expected result: every item passes, or the PR description names the item, the defect, and its follow-up issue.

## Revision 1

**Human comment:** none.
The only issue comment is from Marshall: the first planning run failed with `launch_failed` ("Workspace not trusted") before any plan was written.

**What changed:** nothing was revised, because no earlier plan file exists on this branch (the branch was 0 commits ahead of `master`); this file is the first complete plan, written fresh after the retry.

**Sections updated:** all sections were written new.

## Revision 2

**Human comment:** none.
The bounce is from Marshall: "The implementer hit something it could not get past: TOD-15 (Help tab) not merged to master; plan step 1 says stop. Draft PR: https://github.com/JacquesAttinger/TickTick/pull/26."

**What changed:** the blocker is resolved, so the plan no longer stops on it.
TOD-15 merged to `master` in PR #27, and `HelpView.swift`, `HelpContent.swift`, and `HelpContentTests.swift` are on `origin/master` now.
Step 1 changed from "confirm the merge or stop" to "merge `origin/master` (tip `f37535d`, 13 commits ahead of this branch) into this branch with a normal merge commit, push, and keep using draft PR #26".
A rebase is ruled out because the branch is pushed and PR #26 tracks it, and a rebase would need a force-push.
The brief numbers this revision 1, but this file already holds a "Revision 1" section from the retry after the failed first launch, so this section is numbered 2 to keep the headings unique.

**Sections updated:** TLDR, "What is wrong and why", "Plan" (step 1), and "Decisions made alone".
