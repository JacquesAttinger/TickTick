// Last edited: 2026-09-24 20:16 PT

import AppKit
import SwiftUI

/// The tabs of the Settings window, in order. TT-12 adds Help.
enum SettingsTab: CaseIterable {
    case general
    case shortcuts

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        }
    }
}

/// Owns the one Settings window. It builds the window on the first `open`, and keeps it after a close, so each open
/// shows the same window again, on the tab you used last.
///
/// The window is AppKit (an `NSTabViewController` with toolbar tabs, the standard look of a Mac Settings window), not
/// the SwiftUI `Settings` scene: the popover lives outside every SwiftUI scene, so it could not open that scene (the
/// same reason as the Notes window). `TickTickApp` points the ⌘, menu item here. While the window is open, TickTick
/// has a Dock icon, like with the Notes window (`ActivationPolicyController`).
@MainActor
final class SettingsWindowController {
    static let width: CGFloat = 480

    private let preferences: Preferences
    private let launchAtLogin: LaunchAtLoginModel
    private let activation: ActivationPolicyController
    private var window: NSWindow?
    private var keyObserver: (any NSObjectProtocol)?

    init(preferences: Preferences, launchAtLogin: LaunchAtLoginModel, activation: ActivationPolicyController) {
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.activation = activation
    }

    /// Opens the Settings window, or brings it to the front when it is open.
    func open() {
        let window = window ?? makeWindow()
        launchAtLogin.refresh()
        activation.windowWillShow(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let content = NSHostingController(rootView: makeView(for: tab))
            content.sizingOptions = .preferredContentSize
            let item = NSTabViewItem(viewController: content)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        // The login item can change in System Settings while this window is open. Read it again on each return.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.launchAtLogin.refresh()
            }
        }
        self.window = window
        return window
    }

    private func makeView(for tab: SettingsTab) -> AnyView {
        switch tab {
        case .general: AnyView(GeneralSettingsView(launchAtLogin: launchAtLogin))
        case .shortcuts: AnyView(ShortcutsSettingsView(preferences: preferences))
        }
    }
}
