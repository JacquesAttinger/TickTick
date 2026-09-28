# TT-10: Reorder, in-place completion, time badges

<!-- Last edited: 2026-09-28 17:50 PT -->

**TLDR:** When you check a task in the Notes window, it stays in its row with a filled checkbox, like a checklist in Apple Notes.
Before this change, a checked task went away and you could not see it again.
You can drag a task up or down by the grip at its left.
Each task also shows how long you planned (`est`) and how long its timer really ran (`actual`).

## Change from the plan

`docs/planning.md` (decision 14 and TT-10) asked for a collapsible "Completed (n)" section under the open tasks.
On 2026-09-28, Jacques asked for the Apple Notes behavior instead: a checked task stays in its place, and it does not move to the bottom or to a section.
Decision 14, the behavior defaults, TT-10, the folder layout, and verification step 6 now say this.

## Design

- **One list.** `TaskService.tasks(in:)` gives all the note's tasks, open and done, by `sortIndex`.
  `toggleDone` does not change `sortIndex`, so a task stays in its row when you check or uncheck it.
  `createTask(at:)` and `moveTask(to:)` now count every task, not only open ones.
  `completedTasks(in:)` is gone, because nothing shows a separate completed list.
- **Done rows.** The checkbox is `checkmark.circle.fill` in the accent color, and the title does not change (like Apple Notes).
  A done row has no ▶ and no ⌘↩, and the flow ignores ▶ on it.
  If the task of an open "How long?" prompt gets checked (for example, with Done in the popover), the prompt closes.
  The title of a done task can still be edited.
- **Reorder.** A grip (`line.3.horizontal`) left of the checkbox shows on hover and on the focused row.
  Drag it: a line with a small circle shows where the task will land, and the drop writes `sortIndex` through `TaskService.moveTask`.
  The drag uses its own type, `com.jacquesattinger.TickTick.task-row` (declared in `Info.plist`), so a drop on a title field never types text into it.
  One drop target covers the whole list, and the pointer's height picks the gap between rows.
  The two gaps next to the dragged task show no line, because a drop there does not move it.
- **Time badge.** `⏱ 45m est · 52m actual`, with only the parts that exist.
  The actual time is the sum of the task's closed sessions plus the running timer's active time, so it goes up live and does not count paused time.
  It rounds down to whole minutes (`<1m` under one minute).

## As built

- `TickTick/Model/TaskService.swift`: `tasks(in:)`, full-list indexes for create and move, no `completedTasks`.
- `TickTick/Time/TimeFormatting.swift`: `compact(_:)` (`45m`, `1h 30m`) and `taskBadge(estimateSeconds:actualSeconds:)`.
- `TickTick/Notes/TaskListFlow.swift`: `tasksChanged` carries the done IDs, and `rows` holds every task.
- `TickTick/Notes/TaskListModel.swift`: `timeBadge(for:at:)`, and the drag state (`draggedTaskID`, `dropGap`, `drop(atGap:)`).
- `TickTick/Notes/TaskReorder.swift` (new): the drag type, `TaskDragHandle`, `TaskDropDelegate`, and `DropLine`.
- `TickTick/Notes/TaskTimeBadge.swift` (new): the live badge.
- `TickTick/Notes/TaskRowView.swift` and `NoteDetailView.swift`: the grip column, the done state, the badge, the row frames, and the drop line.
- `TickTickTests/TaskListFlowHarness.swift` (new): the random-event harness moved out of `TaskListFlowTests.swift` (500-line limit), and it now also checks, unchecks, and moves tasks.

## Verify

1. Open Notes and add 4 tasks.
2. Check the second task: it stays second, with a filled checkbox and no ▶.
3. Uncheck it: it stays second.
4. Drag the fourth task by its grip to the top: the drop line shows above the first row, and the task moves there.
5. Drag a done task: it moves too, and it stays checked.
6. Start a timer on a task, pause, extend, and let it run into overtime: the badge's actual time goes up only while the timer counts.
7. Quit and relaunch: the order and the checkmarks are the same.
