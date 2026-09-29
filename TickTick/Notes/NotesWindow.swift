// Last edited: 2026-09-29 18:25 CDT

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
    private let engine: TimerEngine
    private let activation: ActivationPolicyController
    private let sidebar: NotesSidebarModel
    private var window: NSWindow?

    init(
        service: TaskService,
        engine: TimerEngine,
        activation: ActivationPolicyController,
        selectedNoteStore: SelectedNoteStore
    ) {
        self.service = service
        self.engine = engine
        self.activation = activation
        sidebar = NotesSidebarModel(service: service, selectedNoteStore: selectedNoteStore)
    }

    /// Opens the Notes window, or brings it to the front when it is open, and selects the note with `noteID`.
    /// With no `noteID`, the window keeps its selection, also when it opens again. Quick-add saves new tasks in the
    /// selected note, so an open must not move the selection.
    func open(selecting noteID: UUID?) {
        let window = window ?? makeWindow()
        if noteID != nil {
            sidebar.select(noteID: noteID)
        } else {
            sidebar.reload()
        }
        activation.windowWillShow(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: NotesRootView(sidebar: sidebar, service: service, engine: engine)
        )
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
    let engine: TimerEngine

    var body: some View {
        NavigationSplitView {
            NoteSidebarView(model: sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let note = sidebar.selectedNote {
                NoteDetailView(note: note, service: service, engine: engine)
                    .id(note.id)
            }
        }
        .frame(minWidth: NotesWindowController.minimumSize.width, minHeight: NotesWindowController.minimumSize.height)
    }
}
