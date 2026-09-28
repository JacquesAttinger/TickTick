// Last edited: 2026-09-24 19:09 PT

import AppKit
import SwiftUI

/// Owns the one Notes window. It builds the window on the first `open`, and keeps it after a close, so each open
/// shows the same window again with its last size and place.
///
/// The window is AppKit (an `NSWindow` with a SwiftUI root view), not a SwiftUI scene: the popover lives outside
/// every SwiftUI scene, so it could not open a scene window.
@MainActor
final class NotesWindowController {
    static let autosaveName = "NotesWindow"
    static let defaultSize = CGSize(width: 760, height: 520)
    static let minimumSize = CGSize(width: 560, height: 360)

    private let service: TaskService
    private let activation: ActivationPolicyController
    private let sidebar: NotesSidebarModel
    private var window: NSWindow?

    init(service: TaskService, activation: ActivationPolicyController) {
        self.service = service
        self.activation = activation
        sidebar = NotesSidebarModel(service: service)
    }

    /// Opens the Notes window, or brings it to the front when it is open, and selects the note with `noteID`.
    /// With no `noteID`, a window that opens selects the Inbox, and a window that is open keeps its selection.
    func open(selecting noteID: UUID?) {
        let window = window ?? makeWindow()
        if noteID != nil || !window.isVisible {
            sidebar.select(noteID: noteID)
        } else {
            sidebar.reload()
        }
        activation.windowWillShow(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: NotesRootView(sidebar: sidebar, service: service))
        // SwiftUI sets only the smallest size (from `NotesRootView`). You set the size, and the window keeps it.
        hostingController.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "Notes"
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.defaultSize)
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
        self.window = window
        return window
    }
}

/// The content of the Notes window: the note list on the left and the selected note on the right.
struct NotesRootView: View {
    let sidebar: NotesSidebarModel
    let service: TaskService

    var body: some View {
        NavigationSplitView {
            NoteSidebarView(model: sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let note = sidebar.selectedNote {
                NoteDetailView(note: note, openTasks: service.openTasks(in: note))
            }
        }
        .frame(minWidth: NotesWindowController.minimumSize.width, minHeight: NotesWindowController.minimumSize.height)
    }
}
