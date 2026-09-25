// Last edited: 2026-09-24 20:16 PT

import AppKit
import KeyboardShortcuts
import os
import SwiftUI

/// Opens the quick-add panel with the global hotkey (`KeyboardShortcuts.Name.quickAdd` in `ShortcutCatalog`), from
/// any app, and closes it again. The Settings window turns the hotkey off and on (`GlobalHotkeys`).
///
/// Each opening builds a new `QuickAddSession` and a new view, so it always starts on an empty step 1.
/// The panel closes when the flow says so, when it loses key status (a click elsewhere), and on the hotkey again.
@MainActor
final class QuickAddController {
    private static let logger = Logger(subsystem: AppDelegate.bundleIdentifier, category: "QuickAdd")

    private let service: TaskService
    private let engine: TimerEngine
    private let inbox: () throws -> Note
    private let panel = QuickAddPanel()
    private var session: QuickAddSession?
    private var resignObserver: (any NSObjectProtocol)?

    /// - Parameter inbox: returns the Inbox note, for example `ModelStore.bootstrapInbox`.
    init(service: TaskService, engine: TimerEngine, inbox: @escaping () throws -> Note) {
        self.service = service
        self.engine = engine
        self.inbox = inbox
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.session?.send(.focusLost)
            }
        }
    }

    /// Listens for the hotkey. Call it one time, at launch.
    func registerHotkey() {
        KeyboardShortcuts.onKeyUp(for: .quickAdd) { [weak self] in
            self?.toggle()
        }
    }

    /// Opens the panel, or closes it when it is open. Closing works like a click elsewhere: on step 1 nothing is
    /// saved, and after step 1 the task stays without a timer.
    func toggle() {
        if let session, panel.isVisible {
            session.send(.focusLost)
        } else {
            open()
        }
    }

    private func open() {
        let session = QuickAddSession(service: service, engine: engine, inbox: inbox)
        session.onClose = { [weak self, weak session] in
            guard let self, let session, self.session === session else {
                return
            }
            close()
        }
        self.session = session
        let view = QuickAddView(session: session) { [weak self] height in
            self?.panel.setHeight(height)
        }
        let hostingView = NSHostingView(rootView: view)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        let screen = QuickAddPanel.screenWithMouse
        let size = CGSize(width: QuickAddView.width, height: hostingView.fittingSize.height)
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrame(QuickAddPanel.frame(for: size, in: visibleFrame), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        let isKey = panel.isKeyWindow
        Self.logger.notice("Opened quick-add, key: \(isKey, privacy: .public)")
    }

    private func close() {
        session = nil
        panel.orderOut(nil)
        Self.logger.notice("Closed quick-add")
        // The close can come from a button inside the view, so the view goes away on the next turn, not now.
        Task { @MainActor [weak self] in
            guard let self, session == nil else {
                return
            }
            panel.contentView = nil
        }
    }
}
