// Last edited: 2026-09-24 16:50 PT

import Foundation
import Testing
@testable import TickTick

/// The alarm flash keyframes: 3 gentle flashes in 1.5 s, or one slow fade with Reduce Motion.
struct FlashTimelineTests {
    @Test("The standard flash has 3 peaks in about 1.5 s")
    func standardHasThreePeaks() {
        let timeline = FlashTimeline.standard

        #expect(timeline.peakCount == 3)
        #expect(timeline.opacities == [0, 0.6, 0, 0.6, 0, 0.6, 0])
        #expect(timeline.duration == 1.5)
    }

    @Test("The standard flash has at most 2 peaks per second")
    func standardStaysBelowThePhotosensitivityLimit() {
        let timeline = FlashTimeline.standard
        let peakTimes = zip(timeline.opacities, timeline.keyTimes)
            .filter { $0.0 == FlashTimeline.peakOpacity }
            .map { $0.1 * timeline.duration }
        let gaps = zip(peakTimes.dropFirst(), peakTimes).map { $0 - $1 }

        #expect(gaps.count == 2)
        #expect(gaps.allSatisfy { $0 >= 0.5 - 1e-9 })
        #expect(Double(timeline.peakCount) / timeline.duration <= 2)
    }

    @Test("The Reduce Motion flash is one slow fade with the same peak and length")
    func reduceMotionIsOneFade() {
        let timeline = FlashTimeline.reduceMotion

        #expect(timeline.peakCount == 1)
        #expect(timeline.opacities == [0, 0.6, 0])
        #expect(timeline.keyTimes == [0, 0.5, 1])
        #expect(timeline.duration == FlashTimeline.standard.duration)
    }

    @Test("forReduceMotion picks the timeline for the setting")
    func forReduceMotionPicksTheTimeline() {
        #expect(FlashTimeline.forReduceMotion(false) == .standard)
        #expect(FlashTimeline.forReduceMotion(true) == .reduceMotion)
    }

    @Test(
        "Every timeline starts and ends clear, stays in 0...0.6, and has rising key times from 0 to 1",
        arguments: [FlashTimeline.standard, .reduceMotion]
    )
    func keyframesAreWellFormed(timeline: FlashTimeline) {
        #expect(timeline.opacities.first == 0)
        #expect(timeline.opacities.last == 0)
        #expect(timeline.opacities.allSatisfy { (0 ... FlashTimeline.peakOpacity).contains($0) })
        #expect(timeline.keyTimes.count == timeline.opacities.count)
        #expect(timeline.keyTimes.first == 0)
        #expect(timeline.keyTimes.last == 1)
        #expect(zip(timeline.keyTimes.dropFirst(), timeline.keyTimes).allSatisfy { $0 > $1 })
    }
}
