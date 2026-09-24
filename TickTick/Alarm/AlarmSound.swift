// Last edited: 2026-09-24 16:50 PT

import AppKit
import os

/// Plays the alarm sound, the system sound "Glass", one time.
///
/// The app plays it itself, not through the notification, so a Focus mode cannot silence it (product decision 18).
@MainActor
final class AlarmSound {
    static let soundName = NSSound.Name("Glass")
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "AlarmSound")

    /// The sound that plays now. The reference keeps it alive until it ends.
    private var current: NSSound?

    func play() {
        current?.stop()
        // A copy, because the shared named sound does not play again while it still plays.
        guard let sound = NSSound(named: Self.soundName)?.copy() as? NSSound else {
            Self.logger.error("The sound \(Self.soundName, privacy: .public) is missing")
            return
        }
        current = sound
        let started = sound.play()
        Self.logger.notice("Alarm sound \(Self.soundName, privacy: .public) started: \(started)")
    }
}
