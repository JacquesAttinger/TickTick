// Last edited: 2026-09-24 20:16 PT

import SwiftUI

/// The app entry point. The menu bar item and every window live in `AppDelegate` (AppKit).
///
/// The empty `Settings` scene is here because a SwiftUI app needs a scene, and it gives the app its main menu. It
/// never opens: the Settings… menu item (⌘,) opens the AppKit Settings window (`SettingsWindowController`), which
/// the popover can open too.
@main
struct TickTickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
