// Last edited: 2026-09-24 16:50 PT

import AppKit
import QuartzCore

/// The white levels of one alarm flash over time, as a Core Animation keyframe list.
///
/// `standard` flashes 3 times in 1.5 s: each flash takes 0.25 s up to the peak and 0.25 s back down, so there are
/// 2 flashes per second. That is below the photosensitivity limit of 3 flashes per second.
/// `reduceMotion` is one slow fade with the same peak and the same total time, for the Reduce Motion setting.
struct FlashTimeline: Equatable {
    /// The highest white level. 0.6 keeps the screen readable under the flash.
    static let peakOpacity: Float = 0.6
    static let totalDuration: TimeInterval = 1.5

    /// White levels from 0 (clear) to `peakOpacity`. The first and last values are 0.
    let opacities: [Float]
    /// When each level is reached, as a part of `duration` from 0 to 1. Same count as `opacities`.
    let keyTimes: [Double]
    let duration: TimeInterval

    static let standard = FlashTimeline(flashCount: 3)
    static let reduceMotion = FlashTimeline(flashCount: 1)

    /// The timeline for the current Reduce Motion setting.
    static func forReduceMotion(_ reduceMotion: Bool) -> FlashTimeline {
        reduceMotion ? .reduceMotion : .standard
    }

    /// `flashCount` evenly spaced flashes, each one up to the peak and back to 0, in `totalDuration`.
    private init(flashCount: Int) {
        let steps = flashCount * 2
        opacities = (0 ... steps).map { $0.isMultiple(of: 2) ? 0 : Self.peakOpacity }
        keyTimes = (0 ... steps).map { Double($0) / Double(steps) }
        duration = Self.totalDuration
    }

    /// How many times the white reaches its peak.
    var peakCount: Int {
        opacities.count { $0 == Self.peakOpacity }
    }
}

/// Flashes a white overlay over every display when the timer reaches zero (product decision 11).
///
/// Each display gets its own borderless window above everything, also above full-screen apps and the menu bar.
/// The windows ignore the mouse, so clicks go through to the app below. They exist only while a flash runs.
@MainActor
final class FlashController {
    private var windows: [NSWindow] = []
    /// A new value for each flash, so the end of an older flash does not close the windows of a newer one.
    private var flashID = 0

    /// Flashes every display once with the timeline for the current Reduce Motion setting.
    /// A flash that still runs stops first, so two flashes never stack.
    func flash() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        flash(timeline: .forReduceMotion(reduceMotion))
    }

    func flash(timeline: FlashTimeline) {
        closeWindows()
        flashID += 1
        let id = flashID
        windows = NSScreen.screens.map(Self.makeWindow(for:))
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.flashID == id else {
                    return
                }
                self.closeWindows()
            }
        }
        for window in windows {
            window.contentView?.layer?.add(Self.makeAnimation(timeline), forKey: "flash")
            window.orderFrontRegardless()
        }
        CATransaction.commit()
    }

    private func closeWindows() {
        for window in windows {
            window.contentView?.layer?.removeAllAnimations()
            window.orderOut(nil)
            window.close()
        }
        windows = []
    }

    /// A clear window that covers `screen`, with a white layer that starts invisible.
    private static func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.animationBehavior = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor
        // The resting level is clear. Only the animation makes the layer visible.
        view.layer?.opacity = 0
        window.contentView = view
        return window
    }

    private static func makeAnimation(_ timeline: FlashTimeline) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = timeline.opacities.map { NSNumber(value: $0) }
        animation.keyTimes = timeline.keyTimes.map { NSNumber(value: $0) }
        animation.duration = timeline.duration
        animation.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut),
            count: timeline.opacities.count - 1
        )
        return animation
    }
}
