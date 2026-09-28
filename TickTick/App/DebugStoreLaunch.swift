// Last edited: 2026-09-28 17:30 PT

import Foundation

/// The `-debugStorePath PATH` launch argument. It opens the data store at PATH and saves the timer state under its
/// own key, so a test run never reads or changes your real tasks or your real saved timer:
///
///     open build/Build/Products/Debug/TickTick.app --args -debugStorePath /tmp/ticktick-test/TickTick.store
///
/// Quit TickTick first: `open` ignores the arguments when the app already runs. Settings, hotkeys, and the Notes
/// window's frame are still shared with the real app.
enum DebugStoreLaunch {
    static let argument = "debugStorePath"
    /// The `UserDefaults` key of the timer state while the debug store is open.
    static let activeTimerKey = "debugActiveTimer"

    /// The store file from `-debugStorePath PATH`, with `~` expanded. Nil when the argument is missing or blank.
    static func storeURL(in arguments: [String: Any]) -> URL? {
        guard let path = (arguments[argument] as? String)?.trimmingCharacters(in: .whitespaces), !path.isEmpty else {
            return nil
        }
        return URL(filePath: NSString(string: path).expandingTildeInPath, directoryHint: .notDirectory)
    }

    /// The app's objects on the debug store, or nil when the launch arguments have no `-debugStorePath`.
    @MainActor
    static func openCore(arguments: [String: Any]) throws -> AppCore? {
        guard let url = storeURL(in: arguments) else {
            return nil
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppCore(
            modelStore: ModelStore(storeURL: url),
            activeTimerStore: ActiveTimerStore(key: activeTimerKey)
        )
    }
}
