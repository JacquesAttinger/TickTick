// Last edited: 2026-09-24 17:58 PT

import AppKit

/// The floating Spotlight-style window of quick-add.
///
/// It is a non-activating panel: it takes key presses at once, but the app in front stays active, so closing the
/// panel gives the keyboard straight back to that app. It floats above normal windows, shows on every Space, and
/// also shows over a full-screen app.
final class QuickAddPanel: NSPanel {
    /// How far below the top of the screen's visible area the panel's top edge sits, as a part of its height.
    static let topOffsetFraction: CGFloat = 0.22

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: QuickAddView.width, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The panel closes itself when it loses key status, so it must not also hide when the app deactivates.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
    }

    /// A borderless window cannot become key by default, and then it gets no key presses.
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    /// The panel's frame for content `size` on a screen with `visibleFrame`: centered left to right, with the top
    /// edge `topOffsetFraction` of the visible height below the top.
    static func frame(for size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let top = visibleFrame.maxY - (visibleFrame.height * topOffsetFraction).rounded()
        let left = (visibleFrame.midX - size.width / 2).rounded()
        return CGRect(x: left, y: top - size.height, width: size.width, height: size.height)
    }

    /// The screen with the mouse pointer, or the main screen.
    static var screenWithMouse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Changes the height and keeps the top edge where it is, so the panel grows down.
    func setHeight(_ height: CGFloat) {
        var newFrame = frame
        guard height > 0, newFrame.height != height else {
            return
        }
        newFrame.origin.y += newFrame.height - height
        newFrame.size.height = height
        setFrame(newFrame, display: true)
        invalidateShadow()
    }
}
