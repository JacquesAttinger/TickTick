// Last edited: 2026-09-24 19:09 PT

import AppKit
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
/// the popover. The popover is transient, so a click outside it closes it too. When it closes and no TickTick
/// window is open, `ActivationPolicyController` gives the keyboard back to the app that was in front before.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    /// How long after a second changes the refresh fires, so the rounding lands on the new second.
    private static let refreshDelay: TimeInterval = 0.02

    private let engine: TimerEngine
    private let activation: ActivationPolicyController
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let clock: PopoverClock
    private let hostingController: NSHostingController<TimerPopoverView>
    private var refreshTimer: Timer?
    /// A new value on every close, so the next open starts with a clean view (for example no half-typed time).
    private var presentationID = 0

    init(engine: TimerEngine, activation: ActivationPolicyController, statusBar: NSStatusBar = .system) {
        self.engine = engine
        self.activation = activation
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

    /// Opens the popover below the menu bar item, or closes it when it is open.
    /// TT-11 calls this for the global ⌃⌥T shortcut.
    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown, popover.contentViewController?.view.window?.isOnActiveSpace == true {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }
        if popover.isShown {
            // It is still open on a Space you left. Close it at once, so it opens again on this Space.
            popover.close()
        }
        clock.now = engine.clock.now
        activation.activateForClick(NSApp.currentEvent)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // As the key window, the popover draws its controls in their active colors (blue Done, blue bar).
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Makes the popover take key presses, for the "+custom" field.
    private func prepareForTyping() {
        activation.activateForClick(NSApp.currentEvent)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_: Notification) {
        presentationID += 1
        hostingController.rootView = makePopoverView()
        activation.popoverDidClose()
    }

    private func makePopoverView() -> TimerPopoverView {
        TimerPopoverView(engine: engine, clock: clock, presentationID: presentationID) { [weak self] in
            self?.prepareForTyping()
        }
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
