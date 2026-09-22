# TT-2: SwiftData model and task service

<!-- Last edited: 2026-09-22 14:18 CDT -->

**TLDR:** We build the app's "memory": three data types (a note, a task, and a timer session) plus a service that knows all the task rules, like "you cannot delete the Inbox" and "an unchecked task goes back to its old spot".
There is no UI in this issue — only data code and unit tests that prove every rule.
Important: the project scaffold from TT-1 has not merged yet, so the implementation agent must first pull a `master` that contains TT-1 before this code can build.

## Where to find it

Not UI-reachable.
This issue is the data layer: SwiftData model classes, a `ModelStore` that builds the database container, and a `TaskService` with all task operations.
Later issues (TT-4 timer engine, TT-8/TT-9 notes window) call this service; nothing on screen changes here.

## Orientation

The repo is `JacquesAttinger/TODO_TIMER`, the TickTick menu-bar timeboxing app for macOS.
On `origin/master` today the repo contains only `README.md` and `docs/planning.md` — TT-1 (TOD-5), which creates the Xcode scaffold, has not merged and has no remote branch yet.
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
- `TickTick/Model/TaskItem.swift` — new `@Model` class: id, title, isDone, completedAt, sortIndex, estimateSeconds?, note, sessions.
- `TickTick/Model/TimerSession.swift` — new `@Model` class plus the `SessionOutcome` enum (`done / stopped / replaced / deleted`).
- `TickTick/Model/ModelStore.swift` — new: builds the `ModelContainer` (disk or in-memory) and bootstraps the Inbox note idempotently.
- `TickTick/Model/TaskService.swift` — new: every task rule listed above, plus a `TaskServiceError` for the Inbox refusal.
- `TickTickTests/ModelStoreTests.swift` — new: "Inbox is created once" and container bootstrap tests.
- `TickTickTests/TaskServiceTests.swift` — new: one test per service operation, including the four named acceptance tests.

## Plan

Precondition for the implementation agent: fetch and fast-forward `master`, confirm the TT-1 scaffold (`project.yml`, `Makefile`, `TickTick/`, `TickTickTests/`) is present, and rebase this branch onto that tip.
If TT-1 has not merged, stop and report blocked instead of inventing a scaffold.

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
4. Add `TaskService` task operations and queries: `createTask(title:in:at:)` (shifts open-task indexes at and after the slot), `renameTask`, `deleteTask`, `toggleDone(_:)` (sets `completedAt = now` on check, clears it on uncheck, never touches `sortIndex`), `moveTask(_:to:)` (renumbers the note's open tasks 0…n−1), `openTasks(in:)`, `completedTasks(in:)`, and `actualSeconds(for:)`.
   Add the remaining tests: every operation, "uncheck returns the task to its old position" (check a middle task, then uncheck it, and assert its old index), and "actualSeconds sums sessions" (insert sessions directly and assert the sum, including zero sessions = 0).
   Commit with its tests.
5. Finishing pass: confirm every new Swift file starts with `// Last edited: YYYY-MM-DD HH:MM PT`, run `make test lint` once, fix anything red, push, and open the PR linked to TOD-6.

## Decisions made alone

- **Blocked-dependency handling:** TT-1 has not merged and has no remote branch, so the plan makes "rebase onto a master that contains TT-1" an explicit precondition instead of planning a partial scaffold here; duplicating TT-1's scaffold would guarantee conflicts.
- **Outcome storage:** `TimerSession` stores `outcomeRaw: String?` and exposes a computed `outcome: SessionOutcome?` (`String`-backed enum), because a raw string with a default-safe optional is the safest CloudKit-compatible encoding and keeps the migration story trivial.
- **Delete rules:** `Note.tasks` cascades (deleting a note deletes its tasks), but `TaskItem.sessions` nullifies (deleting a task keeps its sessions with `task == nil`), because the behavior default "delete the running task → the session is saved with outcome `deleted`" (planning.md) requires sessions to survive task deletion.
- **Completed list order:** `completedTasks(in:)` sorts by `completedAt` descending (newest first), because planning.md only says "in order" and the TT-10 Completed section reads best newest-first.
- **Open list sort key:** `(sortIndex, createdAt, id)` so that a `sortIndex` tie — possible when open tasks were renumbered while a task sat checked — resolves deterministically and keeps the unchecked task at its old position.
- **Concurrency:** `ModelStore` and `TaskService` are `@MainActor` and `TaskService` takes an injected `ModelContext`, because the app is Swift 6 strict-concurrency and every later caller (timer engine, UI) is main-actor; tests pass the in-memory container's context.
- **Index clamping:** `createTask(at:)` and `moveTask(to:)` clamp the index into the valid range instead of throwing, because a stale UI index should not crash the app.
- **Error surface:** only `deleteNote` throws (`TaskServiceError.cannotDeleteInbox`); the other operations cannot fail meaningfully, so they stay non-throwing to keep call sites simple.
- **Inbox idempotency:** `bootstrapInbox()` fetches before inserting; with no `@Attribute(.unique)` allowed, fetch-then-create is the only guard, and the store is local-only in v1 so there is no sync race.
- **No `make gen` change needed:** TT-1's XcodeGen config globs source folders, so new files under `TickTick/Model/` and `TickTickTests/` join the targets without touching `project.yml`.

## Out of scope found

- **Orphaned sessions have no cleanup** — the nullify delete rule keeps sessions whose task is gone, and nothing ever purges them; fine for v1 stats, a purge could be a later issue.
- **README is a one-line stub** — TT-1's scope includes writing the real README; nothing to do here.
- **Running-task hooks** — "delete or check the running task → stop or done" is TT-4's scope; `TaskService` here only exposes the primitives.

## Verification

Run in the worktree after the rebase precondition:

- `make gen test lint` — build succeeds, every Swift Testing test passes, SwiftLint and SwiftFormat report nothing.
- Test list must include, by name: Inbox cannot be deleted, Inbox is created once, uncheck returns the task to its old position, actualSeconds sums sessions.
- `git diff origin/master --stat` — only files under `TickTick/Model/`, `TickTickTests/`, and `docs/` change.
- No manual UI check exists; this issue ships no UI.
