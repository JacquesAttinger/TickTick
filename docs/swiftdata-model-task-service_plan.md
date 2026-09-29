# TT-2: SwiftData model and task service

<!-- Last edited: 2026-09-24 15:02 PT -->

**TLDR:** We build the app's "memory": three data types (a note, a task, and a timer session) plus a service that knows all the task rules, like "you cannot delete the Inbox" and "an unchecked task goes back to its old spot".
There is no UI in this issue — only data code and unit tests that prove every rule.
The project scaffold from TT-1 is on `master`, so this code builds on it.

## Where to find it

Not UI-reachable.
This issue is the data layer: SwiftData model classes, a `ModelStore` that builds the database container, and a `TaskService` with all task operations.
Later issues (TT-4 timer engine, TT-8/TT-9 notes window) call this service; nothing on screen changes here.

## Orientation

The repo is `JacquesAttinger/TickTick`, the TickTick menu-bar timeboxing app for macOS.
TT-1 (TOD-5) is on `origin/master`: it added `project.yml`, the `Makefile`, `TickTick/App/`, and `TickTickTests/`.
The planned layout (`docs/planning.md`, "Folder layout") puts all data code in `TickTick/Model/` and all tests in `TickTickTests/`.
XcodeGen includes sources by folder glob, so adding files in those folders never touches the project file.
This issue fills `TickTick/Model/` with `Note.swift`, `TaskItem.swift`, `TimerSession.swift`, `ModelStore.swift`, and `TaskService.swift`, and adds Swift Testing tests in `TickTickTests/`.

## What is wrong and why

Nothing is broken; this is a feature gap.
The app has no persistence and no task rules yet.
The shape of the work, from `docs/planning.md` ("Technical approach → SwiftData models" and "Behavior defaults"):

- Three `@Model` classes that are CloudKit-compatible: every property optional or defaulted, no `@Attribute(.unique)`, all relationships optional with explicit inverses.
- `ModelStore` builds the `ModelContainer` (on disk normally, in memory for tests) and creates the Inbox note exactly once on first launch.
- `TaskService` holds every rule: note create/rename/delete (delete refuses Inbox), task create-at-index/rename/delete, toggle done (sets or clears `completedAt`), move (rewrites `sortIndex`), ordered open and completed lists, and `actualSeconds(for:)` as the sum of session `activeSeconds`.
- The uncheck rule works by keeping a done task's `sortIndex` unchanged, so clearing `isDone` puts it back at its old position in the open list.

## Likely touched files

- `TickTick/Model/Note.swift` — new `@Model` class: id, title, createdAt, sortIndex, isInbox, tasks.
- `TickTick/Model/TaskItem.swift` — new `@Model` class: id, title, createdAt, isDone, completedAt, sortIndex, estimateSeconds?, note, sessions.
- `TickTick/Model/TimerSession.swift` — new `@Model` class plus the `SessionOutcome` enum (`done / stopped / replaced / deleted`).
- `TickTick/Model/ModelStore.swift` — new: builds the `ModelContainer` (disk or in-memory) and bootstraps the Inbox note idempotently.
- `TickTick/Model/TaskService.swift` — new: every task rule listed above, plus a `TaskServiceError` for the Inbox refusal.
- `TickTickTests/ModelStoreTests.swift` — new: "Inbox is created once" and container bootstrap tests.
- `TickTickTests/TaskServiceTests.swift` — new: one test per service operation, including the four named acceptance tests.

## Plan

TT-1 is on `master`, and this branch merges `origin/master` before the code commits.

1. Add the three model files in `TickTick/Model/`.
   Every stored property gets a default (`id = UUID()`, `title = ""`, `createdAt = .now`, `sortIndex = 0`, `isDone = false`, `plannedSeconds = 0`, `activeSeconds = 0`) or is optional (`completedAt`, `estimateSeconds`, `endedAt`, all relationships).
   Declare each relationship pair once with an explicit `@Relationship(inverse:)` and the delete rules from "Decisions made alone".
   Store the outcome as a raw `String` with a typed computed property `outcome: SessionOutcome?`.
   Commit: models only (they compile but nothing uses them yet).
2. Add `ModelStore` with `init(inMemory: Bool = false)` building the `ModelContainer` for the three models, plus `bootstrapInbox()` that fetches for an `isInbox` note and creates "Inbox" only when none exists.
   Add `TickTickTests/ModelStoreTests.swift`: an in-memory store creates the Inbox, and calling bootstrap twice still leaves exactly one Inbox.
   Commit with its tests.
3. Add `TaskService` note operations: `createNote(title:)` (appends with next `sortIndex`), `renameNote(_:to:)`, and `deleteNote(_:)` that throws `TaskServiceError.cannotDeleteInbox` when `isInbox` is true.
   Add the note-operation tests to `TickTickTests/TaskServiceTests.swift`, including "Inbox cannot be deleted".
   Commit with its tests.
4. Add `TaskService` task operations and queries: `createTask(title:in:at:)` (puts the task at the open-list index, or at the end when the index is nil), `renameTask`, `deleteTask`, `toggleDone(_:)` (sets `completedAt = now` on check, clears it on uncheck, never touches `sortIndex`), `moveTask(_:to:)` (puts the task at the open-list index; both operations then number all the note's tasks, done ones too, 0…n−1), `openTasks(in:)`, `completedTasks(in:)`, and `actualSeconds(for:)`.
   Add the remaining tests: every operation, "uncheck returns the task to its old position" (check a middle task, then uncheck it, and assert its old index), and "actualSeconds sums sessions" (insert sessions directly and assert the sum, including zero sessions = 0).
   Commit with its tests.
5. Finishing pass: confirm every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, run `make test lint` once, fix anything red, push, and open the PR linked to TOD-6.

## Decisions made alone

- **Dependency:** TT-1 merged before this code was written, so the branch merges `origin/master` and adds no scaffold work.
- **Outcome storage:** `TimerSession` stores `outcomeRaw: String?` and exposes a computed `outcome: SessionOutcome?` (`String`-backed enum), because a raw string with a default-safe optional is the safest CloudKit-compatible encoding and keeps the migration story trivial.
- **Delete rules:** `Note.tasks` cascades (deleting a note deletes its tasks), but `TaskItem.sessions` nullifies (deleting a task keeps its sessions with `task == nil`), because the behavior default "delete the running task → the session is saved with outcome `deleted`" (planning.md) requires sessions to survive task deletion.
- **Completed list order:** `completedTasks(in:)` sorts by `completedAt` descending (newest first), because planning.md only says "in order" and the TT-10 Completed section reads best newest-first.
- **Task order (changed during implementation):** `createTask` and `moveTask` number all the note's tasks 0…n−1, open and done, not only the open ones.
  A new or moved task goes just before the open task that will follow it, or at the very end of the note when no open task follows.
  So a done task always keeps its place between its old neighbors, and unchecking it puts it back there, even after other tasks moved.
  Numbering only the open tasks would give a done task the same `sortIndex` as an open task, and a `createdAt` tie-break does not always pick the old position.
  The sort key stays `(sortIndex, createdAt, id)`, but `createdAt` and `id` now only break ties from outside writes.
  For this, `TaskItem` has a `createdAt` field, which `docs/planning.md` does not list.
- **Concurrency:** `ModelStore` and `TaskService` are `@MainActor` and `TaskService` takes an injected `ModelContext`, because the app is Swift 6 strict-concurrency and every later caller (timer engine, UI) is main-actor; tests pass the in-memory container's context.
- **Index clamping:** `createTask(at:)` and `moveTask(to:)` clamp the index into the valid range instead of throwing, because a stale UI index should not crash the app.
- **Error surface:** only `deleteNote` throws (`TaskServiceError.cannotDeleteInbox`); the other operations cannot fail meaningfully, so they stay non-throwing to keep call sites simple.
- **Save on each change (added during implementation):** every `TaskService` operation calls `context.save()` at once, so the change is on disk before the operation returns.
  A failed save or fetch is logged with `os.Logger`, and SwiftData's autosave tries the save again later.
- **Store file (added during implementation):** the on-disk store is `~/Library/Application Support/com.jacquesattinger.TickTick/TickTick.store`, with CloudKit off.
  The app has no sandbox, so SwiftData's default file (`Application Support/default.store`) could be shared with other apps.
  `ModelStore(storeURL:)` opens any file (nil means in memory), so a test can open the same file two times, like two launches.
- **Time source (added during implementation):** `TaskService(context:now:)` takes a `now` closure for `createdAt` and `completedAt`, so tests can make the completion order certain.
- **Inbox idempotency:** `bootstrapInbox()` fetches before inserting; with no `@Attribute(.unique)` allowed, fetch-then-create is the only guard, and the store is local-only in v1 so there is no sync race.
- **No `make gen` change needed:** TT-1's XcodeGen config globs source folders, so new files under `TickTick/Model/` and `TickTickTests/` join the targets without touching `project.yml`.

## Out of scope found

- **Orphaned sessions have no cleanup** — the nullify delete rule keeps sessions whose task is gone, and nothing ever purges them; fine for v1 stats, a purge could be a later issue.
- **Running-task hooks** — "delete or check the running task → stop or done" is TT-4's scope; `TaskService` here only exposes the primitives.

## Verification

Run in the worktree after the rebase precondition:

- `make gen test lint` — build succeeds, every Swift Testing test passes, SwiftLint and SwiftFormat report nothing.
- Test list must include, by name: Inbox cannot be deleted, Inbox is created once, uncheck returns the task to its old position, actualSeconds sums sessions.
- `git diff origin/master --stat` — only files under `TickTick/Model/`, `TickTickTests/`, and `docs/` change.
- No manual UI check exists; this issue ships no UI.
