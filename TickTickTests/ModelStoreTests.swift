// Last edited: 2026-09-24 14:58 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

@MainActor
struct ModelStoreTests {
    @Test("A new store has only the Inbox note")
    func newStoreHasOnlyTheInbox() throws {
        let store = try ModelStore(inMemory: true)

        let notes = try store.context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        let inbox = try #require(notes.first)
        #expect(inbox.isInbox)
        #expect(inbox.title == "Inbox")
        #expect(inbox.sortIndex == 0)
    }

    @Test("Inbox is created once")
    func inboxIsCreatedOnce() throws {
        let store = try ModelStore(inMemory: true)

        let first = try store.bootstrapInbox()
        let second = try store.bootstrapInbox()

        #expect(first.id == second.id)
        #expect(try inboxCount(in: store.context) == 1)
    }

    @Test("A store file keeps its notes and one Inbox across launches")
    func storeFileKeepsNotesAcrossLaunches() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appending(path: "TickTick.store")

        do {
            let firstLaunch = try ModelStore(storeURL: storeURL)
            firstLaunch.context.insert(Note(title: "Errands", sortIndex: 1))
            try firstLaunch.context.save()
        }
        let secondLaunch = try ModelStore(storeURL: storeURL)

        let notes = try secondLaunch.context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(notes.map(\.title) == ["Inbox", "Errands"])
        #expect(try inboxCount(in: secondLaunch.context) == 1)
    }

    private func inboxCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Note>(predicate: #Predicate { $0.isInbox == true }))
    }
}
