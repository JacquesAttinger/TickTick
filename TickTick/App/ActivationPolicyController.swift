// Last edited: 2026-09-24 19:09 PT

import AppKit
import os

/// The parts of `NSApplication` that `ActivationPolicyController` uses. Tests pass a fake.
@MainActor
protocol ActivationHost: AnyObject {
    var isActive: Bool { get }
    /// True when a normal window of the app (for example the Notes window) is on screen.
    /// The popover, the quick-add panel, and the flash windows do not count.
    var hasOpenWindow: Bool { get }
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    /// Makes TickTick the active app.
    func activateTickTick()
}

extension NSApplication: ActivationHost {
    var hasOpenWindow: Bool {
        windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    /// macOS refuses the newer `activate()` for a click on the status item, so this uses
    /// `activate(ignoringOtherApps:)`.
    func activateTickTick() {
        activate(ignoringOtherApps: true)
    }
}

/// An app that can take the keyboard back from TickTick. `NSRunningApplication` in the app; tests pass a fake.
@MainActor
protocol FocusReturnTarget: AnyObject {
    var isTerminated: Bool { get }
    func takeFocusBack()
}

extension NSRunningApplication: FocusReturnTarget {
    func takeFocusBack() {
        NSApp.yieldActivation(to: self)
        _ = activate(from: .current)
    }
}

/// Decides when TickTick is a menu bar app and when it is a normal app (product decision 4), and who has the keyboard.
///
/// - While a window that it presents (the Notes window) is open, TickTick is a normal app: a Dock icon, an entry in
///   Cmd-Tab, and the main menu (Edit for copy and paste, Window for ⌘W). When the last such window closes, TickTick
///   goes back to the menu bar only.
/// - A click on the menu bar item makes TickTick active, so the popover takes key presses.
/// - When TickTick is active but shows no window (the popover or the Notes window just closed), the keyboard goes
///   back to the app that was in front before. Without this, key presses went nowhere.
@MainActor
final class ActivationPolicyController {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "Activation")

    private let host: any ActivationHost
    /// One close observer for each presented window that is open.
    private var closeObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]
    private var activationObserver: (any NSObjectProtocol)?
    /// The last app other than TickTick that was active.
    private(set) var previousApp: (any FocusReturnTarget)?

    /// - Parameter workspace: tells which app becomes active. Nil in tests, which call `rememberActiveApp`.
    init(host: any ActivationHost = NSApp, workspace: NSWorkspace? = .shared) {
        self.host = host
        guard let workspace else {
            return
        }
        if let front = workspace.frontmostApplication, !Self.isTickTick(front) {
            previousApp = front
        }
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let app, !Self.isTickTick(app) else {
                    return
                }
                self?.rememberActiveApp(app)
            }
        }
    }

    private nonisolated static func isTickTick(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// Stores the app that just became active, so the keyboard can go back to it later.
    func rememberActiveApp(_ app: any FocusReturnTarget) {
        previousApp = app
    }

    // MARK: - Windows

    /// Call it just before `window` shows. TickTick becomes a normal app and the active app, until the window closes.
    func windowWillShow(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        if closeObservers[key] == nil {
            closeObservers[key] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.windowWillClose(key)
                }
            }
        }
        host.setActivationPolicy(.regular)
        host.activateTickTick()
        Self.logger.notice("A window opened: Dock icon on")
    }

    private func windowWillClose(_ key: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
        }
        guard closeObservers.isEmpty else {
            return
        }
        host.setActivationPolicy(.accessory)
        Self.logger.notice("The last window closed: Dock icon off")
        // The window is still on screen while it closes. Check on the next turn, when it is gone.
        Task { @MainActor [weak self] in
            self?.returnFocusIfNoWindow()
        }
    }

    // MARK: - Popover

    /// Makes TickTick active when a mouse click caused the current action, so the popover gets key presses.
    ///
    /// The app has no Dock icon and is not active. Without a click (for example an accessibility press), an
    /// activation makes the transient popover close at once, so the app stays inactive. The buttons work either
    /// way; only typing needs the activation.
    func activateForClick(_ event: NSEvent?) {
        guard !host.isActive, let event, event.type == .leftMouseDown || event.type == .leftMouseUp else {
            return
        }
        host.activateTickTick()
    }

    /// Call it after the popover closes.
    func popoverDidClose() {
        returnFocusIfNoWindow()
    }

    /// Gives the keyboard back to the app that was in front before, when TickTick is active and shows no window.
    /// When the popover closed because you clicked another app, that app is already active, and nothing happens.
    private func returnFocusIfNoWindow() {
        guard host.isActive, !host.hasOpenWindow, let app = previousApp, !app.isTerminated else {
            return
        }
        app.takeFocusBack()
        Self.logger.notice("No window is open: gave the keyboard back to the previous app")
    }
}
