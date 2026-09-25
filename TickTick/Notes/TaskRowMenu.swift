// Last edited: 2026-09-24 19:56 PT

import AppKit
import SwiftUI

/// The right-click menu of a task row: "Delete", and Cut, Copy, and Paste while the title is being edited.
///
/// SwiftUI's `.contextMenu` does not show over a text field: the field shows its own menu instead, and the title
/// fills most of the row. So this AppKit view lies over the whole row and takes only the menu clicks (a right-click
/// or a Control-click). Every other click, the hover, and the pointer shape go to the row under it.
struct TaskRowMenu: NSViewRepresentable {
    /// True while the row's title has the keyboard focus.
    let isEditing: Bool
    let onDelete: () -> Void

    func makeNSView(context _: Context) -> TaskRowMenuView {
        TaskRowMenuView()
    }

    func updateNSView(_ view: TaskRowMenuView, context _: Context) {
        view.isEditing = isEditing
        view.onDelete = onDelete
    }
}

final class TaskRowMenuView: NSView {
    var isEditing = false
    var onDelete: () -> Void = {}

    /// True for the clicks that open a context menu on macOS.
    static func isMenuClick(_ event: NSEvent) -> Bool {
        switch event.type {
        case .rightMouseDown: true
        case .leftMouseDown: event.modifierFlags.contains(.control)
        default: false
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent, Self.isMenuClick(event) else {
            return nil
        }
        return super.hitTest(point)
    }

    /// A Control-click arrives as a left click. A right-click shows the menu through `rightMouseDown` by itself.
    override func mouseDown(with event: NSEvent) {
        guard Self.isMenuClick(event), let menu = menu(for: event) else {
            super.mouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        if isEditing {
            // No target: the items go to the field that edits the title.
            menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
            menu.addItem(.separator())
        }
        let delete = menu.addItem(withTitle: "Delete", action: #selector(deleteTask), keyEquivalent: "")
        delete.target = self
        return menu
    }

    @objc private func deleteTask() {
        onDelete()
    }
}
