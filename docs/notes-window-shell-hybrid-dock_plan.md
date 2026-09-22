# TT-8: Notes window shell, sidebar, hybrid Dock icon

<!-- Last edited: 2026-09-22 12:33 PDT -->

**TLDR:** TickTick lives in the menu bar and normally has no Dock icon.
This issue adds a Notes window with a sidebar of notes (Inbox first), and makes the Dock icon appear only while that window is open.
We build the window with AppKit so the menu bar popover can open it directly, put a placeholder in the detail pane for TT-9, and add "Open Notes" and "Open ↗" buttons to the popover.

## Where to find it

The app has no Dock icon at rest, so you start from the `⏱` item in the menu bar.
Click `⏱` to open the popover, then click "Open Notes" (or "Open ↗" next to the note name while a timer runs).
The Notes window opens, the Dock icon appears, and Cmd-Tab now reaches TickTick.
Close the window and the Dock icon goes away again.
Inside the window, the left sidebar lists notes and the right pane shows the selected note.

## Orientation

The codebase is the TickTick macOS app described in `docs/planning.md` (Swift 6 + SwiftUI, AppKit where needed, XcodeGen project, SwiftData storage).
The repo on `master` currently holds only the docs; the code lands through the TT-1..TT-13 steps.
This issue is step TT-8, the first step of milestone M2 (the Notes window).

The area is `TickTick/Notes/`, which will hold every view of the Notes window, plus `TickTick/App/` for the activation-policy logic.
The part this issue builds is the window shell: the window itself, its lifecycle, and the sidebar.
The exact sections are `NotesWindow.swift` (window + `NavigationSplitView` root), `NoteSidebarView.swift` (note list and note CRUD), `NoteDetailView.swift` (placeholder detail), and `ActivationPolicyController.swift` (hybrid Dock).
It reads and writes notes through `TaskService` and the SwiftData models from TT-2 (`TickTick/Model/`), and it adds two buttons to `TimerPopoverView` from TT-5 (`TickTick/MenuBar/`).

## What is wrong and why

Nothing is broken; this is a feature gap.
After M1 the app can time tasks, but there is no window to see or manage notes, and the app is invisible to the Dock and Cmd-Tab at all times.
Product decision 4 asks for hybrid presence: menu-bar-only at rest, a real app (Dock icon, Cmd-Tab) while the Notes window is open.
The shape of the fix: one AppKit `NSWindow` (hosting a SwiftUI `NavigationSplitView`) managed by a controller with an `open(selecting:)` API, an `ActivationPolicyController` that flips `NSApp.setActivationPolicy` between `.regular` and `.accessory` on window open and close, a sidebar bound to `TaskService`, and popover buttons that call the controller.

**Dependency gate:** this branch was cut before TT-1/TT-2 merged, so the worktree has no code yet.
At implementation start, fetch and rebase onto `master`.
`project.yml`, `Makefile`, `TickTick/Model/` (TT-2) must exist or the run is blocked; steps 1–5 below need only those.
Step 6 (popover buttons) also needs `TickTick/MenuBar/TimerPopoverView.swift` (TT-5); rebase again before that step, and stop and report if TT-5 has still not merged.

## Likely touched files

- `TickTick/Notes/NotesWindow.swift` — new; `NotesWindowController` (creates and reuses one `NSWindow`, `open(selecting:)`, close notification) and `NotesRootView` (the `NavigationSplitView`).
- `TickTick/Notes/NoteSidebarView.swift` — new; note list (Inbox first, then `sortIndex`), ⌘N, double-click rename, context-menu Delete with confirmation.
- `TickTick/Notes/NoteDetailView.swift` — new; selected note title plus a placeholder task list for TT-9 to fill.
- `TickTick/App/ActivationPolicyController.swift` — new; activation policy flip, `NSApp.activate`, and a minimal main menu for while the app is `.regular`.
- `TickTick/Model/TaskService.swift` — extend (from TT-2); add or reuse a sidebar-ordered notes query and a create-note operation that appends at the end.
- `TickTick/MenuBar/TimerPopoverView.swift` — extend (from TT-5); "Open Notes" in idle and active states, "Open ↗" next to the note name.
- `TickTickTests/NoteSidebarTests.swift` — new; ordering and create-note tests with an in-memory container.
- `docs/notes-window-shell-hybrid-dock_plan.md` — this plan.

## Plan

1. **Rebase and gate.**
   Fetch `master` and rebase this branch onto it.
   Confirm `TickTick/Model/TaskService.swift` and `make gen build test lint` work.
   If TT-2 is not on `master`, stop and report the block; no commit for this step.
2. **`TaskService` sidebar operations, with tests.**
   Search `TaskService` first; reuse what TT-2 already ships.
   Ensure these exist: `sidebarNotes()` returning Inbox first and then the other notes by `sortIndex`, and `createNote(title:)` that appends with `sortIndex = max + 1`.
   Add Swift Testing cases in `TickTickTests/NoteSidebarTests.swift`: Inbox is first regardless of `sortIndex`, new note lands last, rename persists, delete refuses Inbox (reuse TT-2's test if present).
3. **Window shell and hybrid Dock.**
   `NotesWindow.swift`: `NotesWindowController` as a `@MainActor` singleton that lazily creates one `NSWindow` with an `NSHostingView` of `NotesRootView`, restores frame with `setFrameAutosaveName`, and exposes `open(selecting noteID: UUID?)`.
   `NotesRootView`: `NavigationSplitView` with `NoteSidebarView` and `NoteDetailView`; selection defaults to Inbox.
   `NoteDetailView`: the note title as a header and a static placeholder list area labeled for TT-9.
   `ActivationPolicyController.swift`: on window open set `.regular`, install a minimal main menu (App, Edit, Window), and `NSApp.activate`; on `NSWindow.willCloseNotification` set `.accessory` and remove nothing else.
   Manual check: open and close 5 times via a temporary debug entry point; Dock icon toggles each time.
4. **Sidebar interactions.**
   ⌘N via a "New Note" button with `.keyboardShortcut("n")` in the sidebar; it creates the note, selects it, and enters rename mode.
   Rename: a per-row `TextField` shown when that row is in edit mode; `onTapGesture(count: 2)` enters it; submit or focus loss commits; an empty title reverts to the old one.
   Context menu → Delete shows a `confirmationDialog` naming the note; Inbox's context menu has no Delete item.
   Deleting the selected note moves the selection to Inbox.
5. **Wire the popover open path behind the controller (no TT-5 yet).**
   Give `NotesWindowController.open(selecting:)` its final signature and make selection-by-id work (used by "Open ↗").
   If the window is already open, `open` brings it to front and changes the selection only.
6. **Popover buttons (needs TT-5 on `master`).**
   Rebase; if `TimerPopoverView.swift` is absent, stop and report the block.
   Add "Open Notes" to the idle and active popover layouts and "Open ↗" next to the note name; both call `NotesWindowController.shared.open(selecting:)`, with "Open ↗" passing the running task's note id, and both close the popover.
7. **Verify, polish, and clean up.**
   Run the full Verification section below, fix anything that looks off in light and dark mode and at small and large sizes, then run `make test lint` once.
   Quit TickTick and kill every process opened during verification.

Every Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, stays under 500 lines, and every function stays under 75 lines.

## Decisions made alone

- **AppKit `NSWindow` + `NSHostingView`, not a SwiftUI `Window` scene.**
  The popover view is hosted in an `NSPopover`, outside any SwiftUI scene, so `@Environment(\.openWindow)` is not available there, and decision 16 forbids a URL scheme as a workaround.
  A controller-owned window gives a reliable programmatic open, one reusable instance, and a clean `willCloseNotification` hook for the activation policy.
  `NotesWindow.swift` keeps the name from the planning doc and holds the SwiftUI root view.
- **Minimal main menu while `.regular`.**
  TT-1's AppDelegate builds no main menu, and without an Edit menu ⌘C/⌘V/⌘X/⌘A do not reach text fields, which breaks renaming; without a Window menu ⌘W does not close.
  A small in-code menu (App with Quit, standard Edit, Window with Close) fixes both and is part of step 3.
- **New note defaults:** title "New Note", appended last (`sortIndex = max + 1`), selected, and immediately in rename mode.
- **Rename commit rule:** commit on submit or focus loss; an empty or whitespace-only title reverts to the previous title.
- **Delete confirmation wording:** "Delete "<title>"? Its tasks are deleted too." with Delete (destructive) and Cancel.
- **Selection fallback:** the window opens with Inbox selected when no selection is passed, and deleting the selected note selects Inbox.
- **Reopen behavior:** `open` on an already-open window brings it to front and updates the selection; it never creates a second window.
- **⌘N scope:** handled inside the Notes window only (it must be key), not as a global hotkey; global hotkeys are TT-7/TT-11 territory.
- **Dependency gating:** steps 1–5 proceed with only TT-2 merged; step 6 waits for TT-5, and the implementer stops and reports instead of stubbing popover code that TT-5 would conflict with.
- **No new UI tests:** per the planning doc, UI is checked by hand; automated tests cover only the pure `TaskService` logic added here.

## Out of scope found

- **Sidebar note reordering** — notes sort by `sortIndex` but no step in the plan gives a UI to change note order (decision 14 covers task reorder only). Filed as a follow-up later; not fixed here.
- **Full main menu (About, Settings…, Help)** — step 3 adds only the minimal menu the window needs; a complete menu belongs with Settings work in TT-11.
- **Detail pane task list** — TT-9 (TOD-14) fills the placeholder; nothing beyond the title and placeholder ships here.

## Verification

Commands, from the worktree root:

```
make gen build test lint
make install
```

Expected: all four targets succeed, tests include the new `NoteSidebarTests`, and TickTick relaunches from `/Applications` with `⏱` in the menu bar and no Dock icon.

Manual checks on the installed app:

1. Popover → "Open Notes", then close the window, 5 times: the Dock icon appears and disappears each time, and Cmd-Tab reaches the window while it is open.
2. ⌘N creates "New Note" in rename mode; type a name and press Return; the note keeps the name.
3. Double-click renames; Esc-equivalent focus loss with an empty field reverts the name.
4. Context menu → Delete asks for confirmation; Inbox shows no Delete item; deleting the selected note selects Inbox.
5. ⌘C/⌘V work inside the rename field; ⌘W closes the window.
6. Start a timer, open the popover, click "Open ↗": the window opens with the running task's note selected.
7. Quit and relaunch: the notes and their order survive.
8. Check light mode, dark mode, the smallest sensible window size, and a large window size; the sidebar and detail pane stay aligned and nothing clips.

After verification: quit TickTick and kill every process started during the checks.
