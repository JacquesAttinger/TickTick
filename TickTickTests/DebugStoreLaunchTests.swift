// Last edited: 2026-09-28 17:30 PT

import Foundation
import Testing
@testable import TickTick

/// `-debugStorePath PATH`: a test run opens its own store and never the real one.
@MainActor
struct DebugStoreLaunchTests {
    @Test("storeURL(in:) reads the path, trims it, and expands ~")
    func storeURLReadsThePath() {
        let url = DebugStoreLaunch.storeURL(in: [DebugStoreLaunch.argument: " /tmp/ticktick-test/TickTick.store "])
        #expect(url?.path == "/tmp/ticktick-test/TickTick.store")

        let home = DebugStoreLaunch.storeURL(in: [DebugStoreLaunch.argument: "~/test/TickTick.store"])
        #expect(home?.path == NSHomeDirectory() + "/test/TickTick.store")
    }

    @Test("storeURL(in:) is nil without the argument, or with a blank or non-text value")
    func storeURLRejectsMissingValues() {
        #expect(DebugStoreLaunch.storeURL(in: [:]) == nil)
        #expect(DebugStoreLaunch.storeURL(in: [DebugStoreLaunch.argument: "  "]) == nil)
        #expect(DebugStoreLaunch.storeURL(in: [DebugStoreLaunch.argument: 3]) == nil)
    }

    @Test("openCore opens the store at the path, with the Inbox, and makes the missing folders")
    func openCoreUsesThePath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "DebugStoreLaunchTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "nested/TickTick.store")

        let core = try #require(try DebugStoreLaunch.openCore(arguments: [DebugStoreLaunch.argument: url.path]))

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(core.taskService.sidebarNotes().map(\.isInbox) == [true])
    }

    @Test("openCore is nil without the argument, so the app opens the real store")
    func openCoreWithoutTheArgument() throws {
        #expect(try DebugStoreLaunch.openCore(arguments: [:]) == nil)
    }
}
