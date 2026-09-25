// Last edited: 2026-09-22 12:36 PT

import AppKit
import Testing
@testable import TickTick

@MainActor
struct ScaffoldTests {
    @Test func bundleIdentifierMatchesTheBuiltApp() {
        #expect(Bundle(for: AppDelegate.self).bundleIdentifier == AppDelegate.bundleIdentifier)
    }

    @Test func statusMenuHasOnlyAQuitItemWiredToTerminate() throws {
        let menu = AppDelegate().makeMenu()

        #expect(menu.items.count == 1)
        let quitItem = try #require(menu.items.first)
        #expect(quitItem.title == "Quit TickTick")
        #expect(quitItem.action == #selector(NSApplication.terminate(_:)))
        #expect(quitItem.target === NSApp)
    }
}
