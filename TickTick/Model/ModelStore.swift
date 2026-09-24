// Last edited: 2026-09-24 14:58 PT

import Foundation
import SwiftData

/// Owns the SwiftData container for the app's models and makes sure the Inbox note exists.
///
/// Keep the store alive as long as you use its `context`: the context stops working when the container goes away.
@MainActor
final class ModelStore {
    static let schema = Schema([Note.self, TaskItem.self, TimerSession.self])
    static let inboxTitle = "Inbox"

    let container: ModelContainer

    var context: ModelContext {
        container.mainContext
    }

    /// Opens the store on disk (the default) or in memory (for tests), then creates the Inbox if it is missing.
    convenience init(inMemory: Bool = false) throws {
        try self.init(storeURL: inMemory ? nil : Self.defaultStoreURL())
    }

    /// Opens the store file at `storeURL`, or an in-memory store when `storeURL` is nil,
    /// then creates the Inbox if it is missing.
    init(storeURL: URL?) throws {
        let configuration = if let storeURL {
            ModelConfiguration(schema: Self.schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: Self.schema, configurations: configuration)
        try bootstrapInbox()
    }

    /// Returns the Inbox note. Creates and saves it first when no Inbox exists, so calling this again is safe.
    @discardableResult
    func bootstrapInbox() throws -> Note {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isInbox == true })
        descriptor.fetchLimit = 1
        if let inbox = try context.fetch(descriptor).first {
            return inbox
        }
        let inbox = Note(title: Self.inboxTitle, sortIndex: 0, isInbox: true)
        context.insert(inbox)
        try context.save()
        return inbox
    }

    /// `~/Library/Application Support/<bundle ID>/TickTick.store`. The app has no sandbox, so SwiftData's
    /// default file (`Application Support/default.store`) could be shared with other apps.
    private static func defaultStoreURL() throws -> URL {
        let folder = URL.applicationSupportDirectory
            .appending(path: AppDelegate.bundleIdentifier, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "TickTick.store", directoryHint: .notDirectory)
    }
}
