// Last edited: 2026-09-29 18:25 CDT

import Foundation

/// Saves the ID of the note that is selected in the Notes window to `UserDefaults`, so the selection survives a
/// close of the window and a quit of the app. Quick-add reads it to know which note gets the new task.
///
/// The ID is text under the key `selectedNoteID`, so `defaults read com.jacquesattinger.TickTick selectedNoteID`
/// shows it.
@MainActor
final class SelectedNoteStore {
    static let defaultKey = "selectedNoteID"

    private let defaults: UserDefaults
    private let key: String

    /// - Parameter key: the app uses the default. Tests and the debug store pass their own key, so they never
    ///   read or change the real selection.
    init(defaults: UserDefaults = .standard, key: String = SelectedNoteStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// The saved ID. Nil when nothing is saved, or when the saved text is not an ID.
    var noteID: UUID? {
        get {
            defaults.string(forKey: key).flatMap { UUID(uuidString: $0) }
        }
        set {
            defaults.set(newValue?.uuidString, forKey: key)
        }
    }

    /// The saved note, or nil when nothing is saved or that note no longer exists.
    func note(in service: TaskService) -> Note? {
        noteID.flatMap { service.note(withID: $0) }
    }
}
