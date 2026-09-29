// Last edited: 2026-09-28 17:15 PT

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A task row that is being dragged to a new place. Only the task list accepts it, so a drag over a title field
    /// never types the task's ID into it. Declared in Info.plist.
    static let tickTickTaskRow = UTType(exportedAs: "com.jacquesattinger.TickTick.task-row")
}

/// The grip left of a task row. Drag it up or down to move the task. It shows on hover and on the row with the
/// keyboard focus.
struct TaskDragHandle: View {
    /// The column left of the checkbox that holds the grip. The draft row keeps the same empty column.
    static let width: CGFloat = 16

    let title: String
    let isShown: Bool
    let onDragStart: () -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: Self.width, height: TaskRowView.iconColumnWidth)
            .contentShape(Rectangle())
            .pointerStyle(.grabIdle)
            .help("Drag to move")
            .accessibilityHidden(true)
            // Hidden, not removed, so every title starts at the same left edge.
            .opacity(isShown ? 1 : 0)
            .onDrag {
                onDragStart()
                return NSItemProvider(item: title as NSString, typeIdentifier: UTType.tickTickTaskRow.identifier)
            } preview: {
                Text(title)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
    }
}

/// The drop target over the whole task list. It turns the pointer's height into a gap between rows, shows the drop
/// line there through the model, and moves the task on drop.
struct TaskDropDelegate: DropDelegate {
    let model: TaskListModel
    /// The middle height of each task row, top to bottom, in the list's coordinate space.
    let rowMidYs: [CGFloat]

    /// The gap for a pointer at `pointerY`: the number of rows whose middle is above it. 0 is above the first row.
    static func gap(forY pointerY: CGFloat, rowMidYs: [CGFloat]) -> Int {
        rowMidYs.count { $0 < pointerY }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.tickTickTaskRow])
    }

    func dropEntered(info: DropInfo) {
        model.dragMoved(toGap: gap(for: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        model.dragMoved(toGap: gap(for: info))
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        model.dragMoved(toGap: nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.drop(atGap: gap(for: info))
    }

    private func gap(for info: DropInfo) -> Int {
        Self.gap(forY: info.location.y, rowMidYs: rowMidYs)
    }
}

/// The line that shows where a dropped task will land.
struct DropLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .strokeBorder(.tint, lineWidth: 2)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(.tint)
                .frame(height: 2)
        }
        .frame(height: 7)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
