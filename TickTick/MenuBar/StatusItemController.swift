// Last edited: 2026-09-24 20:16 PT

import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// The time that the popover shows. `StatusItemController` sets it at the same moment it updates the menu bar
/// label, so the label and the popover always show the same second.
@Observable
@MainActor
final class PopoverClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

/// Owns the menu bar item (`NSStatusItem`) and its popover.
///
/// The label follows the timer: it updates at once on every engine change (through Observation, so also for a
/// rename of the running task) and every second while a timer is active. A click on the item opens or closes
/// the popover, and so does the open-popover hotkey (⌃⌥T). The popover is transient, so a click outside it closes it
/// too. When it closes and no TickTick window is open, `ActivationPolicyController` gives the keyboard back to the
/// app that was in front before. While it is open, `PopoverKeyMonitor` runs the popover keys (Space, D, S, 1, 5, 0).
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    /// How long after a second changes the refresh fires, so the rounding lands on the new second.
    private static let refreshDelay: TimeInterval = 0.02

    private let engine: TimerEngine
    private let activation: ActivationPolicyController
    private let preferences: Preferences
    /// Opens the Notes window and selects the note with the ID, or the Inbox for nil.
    private let openNotes: (UUID?) -> Void
    private let openSettings: () -> Void
    private let keyMonitor: PopoverKeyMonitor
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let clock: PopoverClock
    private let hostingController: NSHostingController<TimerPopoverView>
    private var refreshTimer: Timer?
    /// A new value on every close, so the next open starts with a clean view (for example no half-typed time).
    private var presentationID = 0

    init(
        engine: TimerEngine,
        activation: ActivationPolicyController,
        preferences: Preferences,
        statusBar: NSStatusBar = .system,
        openNotes: @escaping (UUID?) -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.engine = engine
        self.activation = activation
        self.preferences = preferences
        self.openNotes = openNotes
        self.openSettings = openSettings
        keyMonitor = PopoverKeyMonitor(engine: engine, preferences: preferences)
        clock = PopoverClock(now: engine.clock.now)
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        hostingController = NSHostingController(rootView: TimerPopoverView(engine: engine, clock: clock))
        super.init()
        hostingController.rootView = makePopoverView()
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))
        observeEngine()
    }

    /// Opens the popover below the menu bar item, or closes it when it is open. A click on the item calls this.
    @objc func togglePopover(_: Any?) {
        toggle(fromHotkey: false)
    }

    /// The open-popover hotkey (⌃⌥T). TickTick becomes the active app, so the popover keys reach it.
    func togglePopoverFromHotkey() {
        toggle(fromHotkey: true)
    }

    private func toggle(fromHotkey: Bool) {
        if popover.isShown, popover.contentViewController?.view.window?.isOnActiveSpace == true {
            popover.performClose(nil)
        } else {
            showPopover(fromHotkey: fromHotkey)
        }
    }

    private func showPopover(fromHotkey: Bool) {
        guard let button = statusItem.button else {
            return
        }
        if popover.isShown {
            // It is still open on a Space you left. Close it at once, so it opens again on this Space.
            popover.close()
        }
        clock.now = engine.clock.now
        // Settings can have changed the quick-add hint since the last close.
        hostingController.rootView = makePopoverView()
        if fromHotkey {
            activation.activateForHotkey()
        } else {
            activation.activateForClick(NSApp.currentEvent)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // As the key window, the popover draws its controls in their active colors (blue Done, blue bar).
        let window = popover.contentViewController?.view.window
        window?.makeKey()
        keyMonitor.start(for: window)
    }

    /// Makes the popover take key presses, for the "+custom" field.
    private func prepareForTyping() {
        activation.activateForClick(NSApp.currentEvent)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// "Open Notes" and "Open ↗". The window opens first, so the popover closes with a TickTick window open, and
    /// the keyboard stays with TickTick.
    private func openNotesFromPopover(selecting noteID: UUID?) {
        openNotes(noteID)
        popover.performClose(nil)
    }

    /// "Settings…". The window opens first, so the popover closes with a TickTick window open.
    private func openSettingsFromPopover() {
        openSettings()
        popover.performClose(nil)
    }

    func popoverDidClose(_: Notification) {
        keyMonitor.stop()
        presentationID += 1
        hostingController.rootView = makePopoverView()
        activation.popoverDidClose()
    }

    private func makePopoverView() -> TimerPopoverView {
        TimerPopoverView(
            engine: engine,
            clock: clock,
            presentationID: presentationID,
            quickAddKeys: quickAddKeys,
            prepareForTyping: { [weak self] in self?.prepareForTyping() },
            openNotes: { [weak self] noteID in self?.openNotesFromPopover(selecting: noteID) },
            openSettings: { [weak self] in self?.openSettingsFromPopover() }
        )
    }

    /// The keys of the quick-add hotkey for the idle popover's hint, or nil when the hotkey is off or has no keys.
    private var quickAddKeys: String? {
        guard preferences.quickAddHotkeyEnabled, KeyboardShortcuts.getShortcut(for: .quickAdd) != nil else {
            return nil
        }
        return ShortcutCatalog.quickAdd.keysText
    }

    // MARK: - Label

    /// Updates the label now, and again after each engine change. Observation calls `onChange` before the change,
    /// so the update waits for the next main actor turn, when the new state is in place.
    private func observeEngine() {
        withObservationTracking {
            updateLabel()
            restartRefreshTimer()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeEngine()
            }
        }
    }

    private func updateLabel() {
        let now = engine.clock.now
        clock.now = now
        statusItem.button?.attributedTitle = StatusItemLabel.make(
            for: engine.activeTimer,
            taskName: engine.activeTask?.title ?? "",
            now: now
        )
    }

    /// Refreshes the label every second while a timer is active. The first refresh is just after the shown
    /// second changes, so the label never lags up to a second behind the real time. Idle needs no refresh.
    private func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard let timer = engine.activeTimer else {
            return
        }
        let now = engine.clock.now
        let next = StatusItemLabel.nextChange(for: timer, after: now) ?? now.addingTimeInterval(1)
        let first = next.addingTimeInterval(Self.refreshDelay)
        let refresh = Timer(fire: first, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateLabel()
            }
        }
        refresh.tolerance = 0.05
        // The common modes keep it running while a menu is open or the mouse drags.
        RunLoop.main.add(refresh, forMode: .common)
        refreshTimer = refresh
    }
}
