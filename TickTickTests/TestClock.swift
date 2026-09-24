// Last edited: 2026-09-24 15:09 PT

import Foundation
@testable import TickTick

/// A clock that moves only when a test calls `advance(by:)`. Any test file can use it.
final class TestClock: TimerClock {
    var now: Date

    init(now: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now.addTimeInterval(seconds)
    }
}
