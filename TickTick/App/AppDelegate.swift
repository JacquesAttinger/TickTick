// Last edited: 2026-09-24 17:08 PT

import AppKit
import os

/// Owns the app's data and timer objects (`AppCore`), the menu bar item (`StatusItemController`), and the alarm
/// (`AlarmController`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static let bundleIdentifier = "com.jacquesattinger.TickTick"
    private static let logger = Logger(subsystem: bundleIdentifier, category: "AppDelegate")

    /// True when this process hosts the unit tests. The test host must not open the real store or restore the
    /// saved timer.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Nil in the test host, and when the data store cannot open.
    private(set) var core: AppCore?
    private(set) var statusItemController: StatusItemController?
    private(set) var alarmController: AlarmController?
    /// Only when the data store cannot open: a plain `⏱` item with a Quit menu, so the app can still quit.
    private var fallbackStatusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        guard !Self.isRunningUnitTests else {
            return
        }
        guard let core = Self.openCore() else {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = StatusItemLabel.timerSymbol
            item.menu = makeFallbackMenu()
            fallbackStatusItem = item
            return
        }
        self.core = core
        // Connect the timer's listeners (menu bar, alarm) to core.timerEngine here, before startTimer, so they
        // see the restored state and an expiry that happened while the app was quit.
        // The alarm also becomes the notification delegate here, before the launch ends, so a banner button that
        // launched the app reaches it.
        let alarm = AlarmController.makeForApp(engine: core.timerEngine)
        alarmController = alarm
        statusItemController = StatusItemController(engine: core.timerEngine)
        core.startTimer(launchArguments: DebugTimerLaunch.launchArguments)
        alarm.startSyncingNotifications()
    }

    /// The menu of the fallback item. The normal item has the popover, with its own Quit button.
    func makeFallbackMenu() -> NSMenu {
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
