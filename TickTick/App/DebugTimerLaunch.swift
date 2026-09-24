// Last edited: 2026-09-24 15:22 PT

import Foundation

/// The `-debugStartTimerSeconds N` launch argument. It starts an N-second timer at launch on an open Inbox task
/// named "Debug timer", so you can test the menu bar, the alarm, and quick-add before any UI can start a timer:
///
///     open build/Build/Products/Debug/TickTick.app --args -debugStartTimerSeconds 60
///
/// Quit TickTick first: `open` ignores the arguments when the app already runs.
/// It also works in Release builds, because `make install` builds Release.
enum DebugTimerLaunch {
    static let argument = "debugStartTimerSeconds"
    static let taskTitle = "Debug timer"

    /// The `-name value` launch arguments, as `UserDefaults` reads them. Only this domain counts, so a value that
    /// was saved with `defaults write` never starts a timer.
    static var launchArguments: [String: Any] {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    /// N from `-debugStartTimerSeconds N` when N is a number of seconds above 0 and not over 24 h, else nil.
    static func seconds(in arguments: [String: Any]) -> TimeInterval? {
        let value: TimeInterval? = switch arguments[argument] {
        case let text as String: TimeInterval(text.trimmingCharacters(in: .whitespaces))
        case let number as NSNumber: number.doubleValue
        default: nil
        }
        guard let value, value > 0, value <= DurationParser.maximumSeconds else {
            return nil
        }
        return value
    }

    /// Starts a `seconds` timer on the open Inbox task "Debug timer" and replaces any active timer.
    /// It reuses that task when it exists, so repeated launches do not add tasks. Like quick-add, it sets the estimate.
    @MainActor
    @discardableResult
    static func start(seconds: TimeInterval, service: TaskService, engine: TimerEngine, inbox: Note) -> TaskItem {
        let task = service.openTasks(in: inbox).first { $0.title == taskTitle }
            ?? service.createTask(title: taskTitle, in: inbox)
        service.setEstimate(seconds, for: task)
        engine.start(task: task, seconds: seconds, replacing: true)
        return task
    }
}
