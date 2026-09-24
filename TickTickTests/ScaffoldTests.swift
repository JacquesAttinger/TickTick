// Last edited: 2026-09-24 16:43 PT

import AppKit
import Testing
@testable import TickTick

@MainActor
struct ScaffoldTests {
    @Test func bundleIdentifierMatchesTheBuiltApp() {
        #expect(Bundle(for: AppDelegate.self).bundleIdentifier == AppDelegate.bundleIdentifier)
    }

    @Test func fallbackMenuHasOnlyAQuitItemWiredToTerminate() throws {
        let menu = AppDelegate().makeFallbackMenu()

        #expect(menu.items.count == 1)
        let quitItem = try #require(menu.items.first)
        #expect(quitItem.title == "Quit TickTick")
        #expect(quitItem.action == #selector(NSApplication.terminate(_:)))
        #expect(quitItem.target === NSApp)
    }
}
