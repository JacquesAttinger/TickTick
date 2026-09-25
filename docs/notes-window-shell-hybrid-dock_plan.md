# TT-8: Notes window shell, sidebar, hybrid Dock icon

<!-- Last edited: 2026-09-24 19:06 PT -->

**TLDR:** TickTick lives in the menu bar and normally has no Dock icon.
This issue adds a Notes window with a sidebar of notes (Inbox first), and makes the Dock icon appear only while that window is open.
We build the window with AppKit so the menu bar popover can open it directly, show a read-only task list in the detail pane until TT-9, and add "Open Notes" and "Open ↗" buttons to the popover.
It also fixes a TT-5 bug: after the popover closed, TickTick kept the keyboard with no window, so key presses went nowhere.

## Where to find it

The app has no Dock icon at rest, so you start from the `⏱` item in the menu bar.
Click `⏱` to open the popover, then click "Open Notes" (or "Open ↗" next to the note name while a timer runs).
The Notes window opens, the Dock icon appears, and Cmd-Tab now reaches TickTick.
Close the window and the Dock icon goes away again.
Inside the window, the left sidebar lists notes and the right pane shows the selected note.

## Orientation

The codebase is the TickTick macOS app described in `docs/planning.md` (Swift 6 + SwiftUI, AppKit where needed, XcodeGen project, SwiftData storage).
TT-1 to TT-4 are on `master`.
This branch also merges the open TT-5, TT-6, and TT-7 branches, because the popover buttons need TT-5.
This issue is step TT-8, the first step of milestone M2 (the Notes window).

The area is `TickTick/Notes/`, which will hold every view of the Notes window, plus `TickTick/App/` for the activation-policy logic.
The part this issue builds is the window shell: the window itself, its lifecycle, and the sidebar.
The exact sections are `NotesWindow.swift` (window + `NavigationSplitView` root), `NotesSidebarModel.swift` (sidebar state and rules), `NoteSidebarView.swift` (note list), `NoteDetailView.swift` (placeholder detail), and `ActivationPolicyController.swift` (hybrid Dock and keyboard focus).
It reads and writes notes through `TaskService` and the SwiftData models from TT-2 (`TickTick/Model/`), and it adds two buttons to `TimerPopoverView` from TT-5 (`TickTick/MenuBar/`).

## What is wrong and why

Nothing is broken; this is a feature gap.
After M1 the app can time tasks, but there is no window to see or manage notes, and the app is invisible to the Dock and Cmd-Tab at all times.
Product decision 4 asks for hybrid presence: menu-bar-only at rest, a real app (Dock icon, Cmd-Tab) while the Notes window is open.
The shape of the fix: one AppKit `NSWindow` (hosting a SwiftUI `NavigationSplitView`) managed by a controller with an `open(selecting:)` API, an `ActivationPolicyController` that flips `NSApp.setActivationPolicy` between `.regular` and `.accessory` on window open and close, a sidebar model bound to `TaskService`, and popover buttons that call the controller.

**TT-5 focus bug:** a click on the menu bar item activates TickTick, so the popover can take typing.
When the popover closed (a second click or Esc), TickTick stayed the active app with no window, so key presses went nowhere.
`ActivationPolicyController` now remembers the last other active app, and gives it the keyboard back when TickTick is active but shows no window (after the popover closes, and after the Notes window closes).

**Dependency gate:** resolved.
TT-1 and TT-2 are on `master`, and the branch merges the TT-5 to TT-7 branches (PRs #16, #17, #18 merge first).

## Likely touched files

- `TickTick/Notes/NotesWindow.swift` — new; `NotesWindowController` (creates and reuses one `NSWindow`, `open(selecting:)`) and `NotesRootView` (the `NavigationSplitView`).
- `TickTick/Notes/NotesSidebarModel.swift` — new; `@Observable` sidebar state: notes, selection, rename field, delete question.
- `TickTick/Notes/NoteSidebarView.swift` — new; note list (Inbox first, then `sortIndex`), ⌘N, double-click rename, context-menu Rename and Delete… with confirmation.
- `TickTick/Notes/NoteDetailView.swift` — new; selected note title plus the note's open tasks as read-only text, for TT-9 to replace.
- `TickTick/App/ActivationPolicyController.swift` — new; activation policy flip, activation on a status item click, and the keyboard hand-back.
- `TickTick/App/AppDelegate.swift` — extend; owns `ActivationPolicyController` and `NotesWindowController`.
- `TickTick/Model/TaskService.swift` — extend (from TT-2); `sidebarNotes()` and `note(withID:)`. `createNote(title:)` already appends at the end.
- `TickTick/MenuBar/StatusItemController.swift` and `TimerPopoverView.swift` — extend (from TT-5); "Open Notes" in the footer, "Open ↗" next to the note name, and the activation calls.
- `TickTickTests/NoteSidebarTests.swift`, `TickTickTests/ActivationPolicyControllerTests.swift` — new.
- `docs/notes-window-shell-hybrid-dock_plan.md` — this plan.

## Plan

1. **Merge and gate.**
   Merge `master` and the TT-7 branch (which has TT-5 and TT-6) into this branch.
   Confirm `make build test lint` work.
   Reproduce the TT-5 focus bug on the Debug build before the fix.
2. **`TaskService` sidebar operations, with tests.**
   Search `TaskService` first; reuse what TT-2 already ships.
   Ensure these exist: `sidebarNotes()` returning Inbox first and then the other notes by `sortIndex`, and `createNote(title:)` that appends with `sortIndex = max + 1`.
   Add Swift Testing cases in `TickTickTests/NoteSidebarTests.swift`: Inbox is first regardless of `sortIndex`, new note lands last, rename persists, delete refuses Inbox (reuse TT-2's test if present).
3. **Window shell and hybrid Dock.**
   `NotesWindow.swift`: `NotesWindowController` (owned by `AppDelegate`, not a singleton) lazily creates one `NSWindow` with an `NSHostingController` of `NotesRootView`, restores the frame with `setFrameAutosaveName`, and exposes `open(selecting noteID: UUID?)`.
   `NotesRootView`: `NavigationSplitView` with `NoteSidebarView` and `NoteDetailView`; selection defaults to Inbox.
   `NoteDetailView`: the note title as a header and the note's open tasks as read-only text until TT-9.
   `ActivationPolicyController.swift`: on window open set `.regular` and activate; on `NSWindow.willCloseNotification` set `.accessory` and give the keyboard back to the app that was in front before.
   The SwiftUI app already installs a full main menu (TickTick, Edit, View, Window, Help), so no own menu is needed.
   Unit tests cover the policy flips and the keyboard hand-back with a fake host.
4. **Sidebar interactions.**
   ⌘N via a "New Note" button with `.keyboardShortcut("n")` in the sidebar; it creates the note, selects it, and enters rename mode.
   Rename: a per-row `TextField` shown when that row is in edit mode; a double-click (the `primaryAction` of `contextMenu(forSelectionType:)`) or "Rename" enters it; submit or focus loss commits; Esc cancels; an empty title reverts to the old one.
   Context menu → Delete… shows a `confirmationDialog` naming the note; Inbox's context menu has only Rename.
   Deleting the selected note moves the selection to Inbox.
5. **Open by note ID.**
   Give `NotesWindowController.open(selecting:)` its final signature and make selection-by-id work (used by "Open ↗").
   If the window is already open, `open` brings it to front and changes the selection only.
6. **Popover buttons and the focus fix.**
   "Open Notes" (in the footer, so in idle and active layouts) and "Open ↗" next to the note name call an `openNotes` closure that `StatusItemController` gets from `AppDelegate`.
   "Open ↗" passes the running task's note id.
   The window opens first, then the popover closes, so the keyboard stays with TickTick.
   The status item click activation moves into `ActivationPolicyController`, and `popoverDidClose` asks it to hand the keyboard back.
7. **Verify, polish, and clean up.**
   Run the full Verification section below, fix anything that looks off in light and dark mode and at small and large sizes, then run `make test lint` once.
   Quit TickTick and kill every process opened during verification.

Every Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, stays under 500 lines, and every function stays under 75 lines.

## Decisions made alone

- **AppKit `NSWindow` + `NSHostingController`, not a SwiftUI `Window` scene.**
  The popover view is hosted in an `NSPopover`, outside any SwiftUI scene, so `@Environment(\.openWindow)` is not available there, and decision 16 forbids a URL scheme as a workaround.
  A controller-owned window gives a reliable programmatic open, one reusable instance, and a clean `willCloseNotification` hook for the activation policy.
  `NotesWindow.swift` keeps the name from the planning doc and holds the SwiftUI root view.
- **No own main menu.**
  The plan asked for a minimal menu, but the SwiftUI `App` already installs TickTick, Edit, View, Window, and Help menus.
  ⌘C/⌘V work in the rename field and ⌘W closes the window with it, so an own menu would only duplicate it.
- **No singleton.**
  `AppDelegate` owns `NotesWindowController` and passes an `openNotes` closure to `StatusItemController`, like the other controllers.
- **Keyboard hand-back.**
  `ActivationPolicyController` tracks the last other active app with `NSWorkspace.didActivateApplicationNotification`.
  When TickTick is active and has no normal window on screen, it yields activation to that app.
- **New note defaults:** title "New Note", appended last (`sortIndex = max + 1`), selected, and immediately in rename mode.
- **Rename commit rule:** commit on submit or focus loss; an empty or whitespace-only title reverts to the previous title.
- **Delete confirmation wording:** "Delete "<title>"? Its tasks are deleted too." with Delete (destructive) and Cancel.
- **Selection fallback:** the window opens with Inbox selected when no selection is passed, and deleting the selected note selects Inbox.
  A click on empty space in the list keeps the selection, so a note is always selected.
- **Reopen behavior:** `open` on an already-open window brings it to front and updates the selection; it never creates a second window.
  "Open Notes" on an open window keeps its selection.
- **Window size:** 760 × 520 at first, 560 × 360 at least, and the last size and place are saved.
- **⌘N scope:** handled inside the Notes window only (it must be key), not as a global hotkey; global hotkeys are TT-7/TT-11 territory.
- **Dependency gating:** steps 1–5 proceed with only TT-2 merged; step 6 waits for TT-5, and the implementer stops and reports instead of stubbing popover code that TT-5 would conflict with.
- **No new UI tests:** per the planning doc, UI is checked by hand; automated tests cover `TaskService`, `NotesSidebarModel`, and `ActivationPolicyController` (with a fake host).

## Out of scope found

- **Sidebar note reordering** — notes sort by `sortIndex` but no step in the plan gives a UI to change note order (decision 14 covers task reorder only). Filed as a follow-up later; not fixed here.
- **Full main menu (About, Settings…, Help)** — step 3 adds only the minimal menu the window needs; a complete menu belongs with Settings work in TT-11.
- **Detail pane task list** — TT-9 (TOD-14) replaces the read-only task text with task rows.
- **App icon** — the app has no icon, so the Dock and Cmd-Tab show the generic app icon. Left for TT-13.
- **Cmd-Tab order** — TickTick becomes a normal app after it is already active, so Cmd-Tab lists it last, not first, until you switch to it one time.

## Verification

Commands, from the worktree root:

```
make build test lint
open build/Build/Products/Debug/TickTick.app
```

Expected: all targets succeed, tests include the new `NoteSidebarTests` and `ActivationPolicyControllerTests`, and TickTick starts with `⏱` in the menu bar and no Dock icon.

Manual checks on the Debug app (the step brief forbids `make install`):

1. Popover → "Open Notes", then close the window, 5 times: the Dock icon appears and disappears each time, and Cmd-Tab reaches the window while it is open.
2. ⌘N creates "New Note" in rename mode; type a name and press Return; the note keeps the name.
3. Double-click renames; Esc-equivalent focus loss with an empty field reverts the name.
4. Context menu → Delete asks for confirmation; Inbox shows no Delete item; deleting the selected note selects Inbox.
5. ⌘C/⌘V work inside the rename field; ⌘W closes the window.
6. Start a timer, open the popover, click "Open ↗": the window opens with the running task's note selected.
7. Quit and relaunch: the notes and their order survive.
8. Check light mode, dark mode, the smallest sensible window size, and a large window size; the sidebar and detail pane stay aligned and nothing clips.
9. With a TextEdit document in front, click `⏱`, then close the popover with a second click and with Esc: TextEdit is in front again and typed text lands in it.

After verification: quit TickTick and kill every process started during the checks.
