// Last edited: 2026-09-22 12:27 PT

import Foundation
import Testing
@testable import TickTick

@MainActor
struct ScaffoldTests {
    @Test func bundleIdentifierMatchesTheBuiltApp() {
        #expect(Bundle(for: AppDelegate.self).bundleIdentifier == AppDelegate.bundleIdentifier)
    }
}
