// Last edited: 2026-09-24 20:16 PT

import AppKit

/// A single key that controls the timer while the popover is open (product decision 15).
/// `ShortcutCatalog` lists these same cases, so the keys that work and the keys that the Help tab shows are the same.
enum PopoverKeyCommand: CaseIterable, Equatable {
    case pauseOrResume
    case done
    case stop
    case addOneMinute
    case addFiveMinutes
    case addTenMinutes

    /// The character that the key types, in lowercase (`NSEvent.charactersIgnoringModifiers`).
    var character: String {
        switch self {
        case .pauseOrResume: " "
        case .done: "d"
        case .stop: "s"
        case .addOneMinute: "1"
        case .addFiveMinutes: "5"
        case .addTenMinutes: "0"
        }
    }

    /// The name of the key, as the Settings window and the Help tab show it.
    var keyName: String {
        self == .pauseOrResume ? "Space" : character.uppercased()
    }

    /// What the key does, in a few words.
    var description: String {
        switch self {
        case .pauseOrResume: "Pause or resume the timer"
        case .done: "Done: stop the timer and check the task"
        case .stop: "Stop the timer and keep the task open"
        case .addOneMinute: "Add 1 minute"
        case .addFiveMinutes: "Add 5 minutes"
        case .addTenMinutes: "Add 10 minutes"
        }
    }

    /// The time that an add key adds (+1 / +5 / +10 min), or nil for the other keys.
    var extensionSeconds: TimeInterval? {
        switch self {
        case .addOneMinute: 60
        case .addFiveMinutes: 300
        case .addTenMinutes: 600
        case .pauseOrResume, .done, .stop: nil
        }
    }

    /// The command for the typed characters, or nil when the key has none. D and S also work with Shift.
    static func command(for characters: String) -> PopoverKeyCommand? {
        let key = characters.lowercased()
        return allCases.first { $0.character == key }
    }
}

/// The rules for a key press in the popover. They are pure, so the tests need no events and no window.
enum PopoverKeyHandler {
    enum Decision: Equatable {
        /// The key is not a popover key now. It goes on to the popover as usual.
        case pass
        /// The key is a popover key, but it does nothing (a held key repeats). It does not go on, so no beep.
        case ignore
        case run(PopoverKeyCommand)
    }

    /// The parts of a key press that the rules need. Unlike `NSEvent`, it can go into the main actor.
    struct KeyPress: Sendable {
        var characters: String
        var modifiers: NSEvent.ModifierFlags = []
        var isRepeat = false
    }

    /// The state of the app at the key press.
    struct Situation {
        /// The "Popover keys" switch in Settings.
        var keysEnabled = true
        /// A timer runs, is paused, or is in overtime. The idle popover has no timer to control.
        var timerIsActive = true
        /// A text field (the "+custom" field) has the keyboard. It must get Space and the digits.
        var isEditingText = false
    }

    /// Only the plain key works. With ⌘, ⌃, or ⌥ it goes on (for example ⌘, for Settings). Shift is allowed.
    private static let blockingModifiers: NSEvent.ModifierFlags = [.command, .control, .option]

    static func decision(for press: KeyPress, in situation: Situation) -> Decision {
        guard situation.keysEnabled, situation.timerIsActive, !situation.isEditingText,
              press.modifiers.isDisjoint(with: blockingModifiers),
              let command = PopoverKeyCommand.command(for: press.characters)
        else {
            return .pass
        }
        return press.isRepeat ? .ignore : .run(command)
    }

    /// Runs the command on the timer. Space in overtime beeps: overtime cannot pause (decision 12), like the
    /// dimmed Pause button.
    @MainActor
    static func perform(_ command: PopoverKeyCommand, on engine: TimerEngine, beep: () -> Void = NSSound.beep) {
        switch command {
        case .pauseOrResume:
            switch engine.activeTimer?.phase {
            case .running: engine.pause()
            case .paused: engine.resume()
            case .overtime, nil: beep()
            }
        case .done:
            engine.done()
        case .stop:
            engine.stop()
        case .addOneMinute, .addFiveMinutes, .addTenMinutes:
            if let seconds = command.extensionSeconds {
                engine.extend(seconds: seconds)
            }
        }
    }
}

/// Watches key presses while the popover is open and runs the popover keys. `StatusItemController` starts it when
/// the popover shows and stops it when the popover closes, so the keys work only while the popover is open.
@MainActor
final class PopoverKeyMonitor {
    private let engine: TimerEngine
    private let preferences: Preferences
    private var monitor: Any?

    init(engine: TimerEngine, preferences: Preferences) {
        self.engine = engine
        self.preferences = preferences
    }

    /// Starts to watch the key presses that go to `window` (the popover's window). Other windows are not affected.
    func start(for window: NSWindow?) {
        stop()
        guard let window else {
            return
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            let press = PopoverKeyHandler.KeyPress(
                characters: event.charactersIgnoringModifiers ?? "",
                modifiers: event.modifierFlags,
                isRepeat: event.isARepeat
            )
            let windowNumber = event.windowNumber
            // AppKit calls local monitors on the main thread.
            let isUsed = MainActor.assumeIsolated {
                guard let self, let window, windowNumber == window.windowNumber else {
                    return false
                }
                return self.handle(press, in: window)
            }
            return isUsed ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Returns true when the key was a popover key, so it must not go on to the popover.
    private func handle(_ press: PopoverKeyHandler.KeyPress, in window: NSWindow) -> Bool {
        let situation = PopoverKeyHandler.Situation(
            keysEnabled: preferences.popoverKeysEnabled,
            timerIsActive: engine.activeTimer != nil,
            // A text field edits through its field editor, an `NSTextView`.
            isEditingText: window.firstResponder is NSText
        )
        switch PopoverKeyHandler.decision(for: press, in: situation) {
        case .pass:
            return false
        case .ignore:
            return true
        case let .run(command):
            PopoverKeyHandler.perform(command, on: engine)
            return true
        }
    }
}
