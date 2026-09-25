// Last edited: 2026-09-24 14:58 PT

import Foundation
import SwiftData

/// How a timer session ended.
enum SessionOutcome: String, CaseIterable, Sendable {
    case done
    case stopped
    case replaced
    case deleted
}

/// One run of the timer on a task. A task's actual time is the sum of its sessions' `activeSeconds`.
///
/// CloudKit-compatible: every property has a default or is optional, and nothing is unique.
@Model
final class TimerSession {
    var id: UUID = UUID()
    /// Nil after the task is deleted; the session stays as a record.
    var task: TaskItem?
    var startedAt: Date = Date.now
    var endedAt: Date?
    var plannedSeconds: TimeInterval = 0
    /// Running time plus overtime, without paused time.
    var activeSeconds: TimeInterval = 0
    /// The raw value of `outcome`. Nil while the session runs.
    var outcomeRaw: String?

    var outcome: SessionOutcome? {
        get { outcomeRaw.flatMap(SessionOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    init(startedAt: Date = .now, plannedSeconds: TimeInterval = 0, activeSeconds: TimeInterval = 0) {
        self.startedAt = startedAt
        self.plannedSeconds = plannedSeconds
        self.activeSeconds = activeSeconds
    }
}
