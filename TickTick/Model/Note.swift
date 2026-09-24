// Last edited: 2026-09-24 14:58 PT

import Foundation
import SwiftData

/// A titled list of tasks. The Inbox note is created once by `ModelStore` and cannot be deleted.
///
/// CloudKit-compatible: every property has a default or is optional, and nothing is unique.
@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now
    /// Sidebar order. The Inbox is 0 and new notes get the next free index, so the Inbox sorts first.
    var sortIndex: Int = 0
    var isInbox: Bool = false

    /// Deleting a note deletes its tasks.
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.note)
    var tasks: [TaskItem]? = []

    init(title: String, sortIndex: Int, isInbox: Bool = false, createdAt: Date = .now) {
        self.title = title
        self.sortIndex = sortIndex
        self.isInbox = isInbox
        self.createdAt = createdAt
    }
}
