// Last edited: 2026-09-24 17:58 PT

import CoreGraphics
import Testing
@testable import TickTick

@MainActor
struct QuickAddPanelTests {
    @Test("The panel is centered left to right, with its top edge 22% below the top of the visible area")
    func frameOnAScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)

        let frame = QuickAddPanel.frame(for: CGSize(width: 560, height: 60), in: visible)

        #expect(frame == CGRect(x: 476, y: 944 - 208 - 60, width: 560, height: 60))
    }

    @Test("A screen that does not start at 0,0 (a second display) keeps the same placement")
    func frameOnASecondScreen() {
        let visible = CGRect(x: -1920, y: 200, width: 1920, height: 1055)

        let frame = QuickAddPanel.frame(for: CGSize(width: 560, height: 180), in: visible)

        #expect(frame.midX == visible.midX)
        #expect(frame.maxY == visible.maxY - 232)
        #expect(frame.size == CGSize(width: 560, height: 180))
    }
}
