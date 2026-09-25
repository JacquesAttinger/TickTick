// Last edited: 2026-09-24 14:58 PT

import Foundation
import SwiftData

/// One checkbox row in a note. Named `TaskItem` so it does not hide Swift's `Task`.
///
/// CloudKit-compatible: every property has a default or is optional, and nothing is unique.
@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    var isDone: Bool = false
    var completedAt: Date?
    /// Position in the note. A done task keeps its value, so unchecking it puts it back in its old place.
    var sortIndex: Int = 0
    var estimateSeconds: TimeInterval?
    var note: Note?

    /// Deleting a task keeps its sessions (their `task` becomes nil), so a deleted running task still has a record.
    @Relationship(deleteRule: .nullify, inverse: \TimerSession.task)
    var sessions: [TimerSession]? = []

    init(title: String, sortIndex: Int = 0, createdAt: Date = .now) {
        self.title = title
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
