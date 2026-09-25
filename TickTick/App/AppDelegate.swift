// Last edited: 2026-09-24 15:20 PT

import AppKit
import os

/// Owns the menu bar status item and the app's data and timer objects (`AppCore`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleIdentifier = "com.jacquesattinger.TickTick"
    private static let logger = Logger(subsystem: bundleIdentifier, category: "AppDelegate")

    /// True when this process hosts the unit tests. The test host must not open the real store or restore the
    /// saved timer.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var statusItem: NSStatusItem?
    /// Nil in the test host, and when the data store cannot open.
    private(set) var core: AppCore?

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⏱"
        item.menu = makeMenu()
        statusItem = item

        guard !Self.isRunningUnitTests, let core = Self.openCore() else {
            return
        }
        self.core = core
        // Connect the timer's listeners (menu bar, alarm) to core.timerEngine here, before startTimer, so they
        // see the restored state and an expiry that happened while the app was quit.
        core.startTimer(launchArguments: DebugTimerLaunch.launchArguments)
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit TickTick",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: ""
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
        return menu
    }

    private static func openCore() -> AppCore? {
        do {
            return try AppCore(modelStore: ModelStore())
        } catch {
            logger.fault("Opening the data store failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
