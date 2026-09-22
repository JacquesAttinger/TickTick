// Last edited: 2026-09-22 12:36 PT

import AppKit

/// Owns the menu bar status item.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let bundleIdentifier = "com.jacquesattinger.TickTick"

    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⏱"
        item.menu = makeMenu()
        statusItem = item
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: "Quit TickTick",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
        return menu
    }
}
