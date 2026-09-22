// Last edited: 2026-09-22 12:27 PT

import SwiftUI

/// The app entry point. The menu bar item lives in `AppDelegate` (AppKit);
/// the empty `Settings` scene is the only SwiftUI scene until TT-11 fills it in.
@main
struct TickTickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
