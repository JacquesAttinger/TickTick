// Last edited: 2026-09-24 15:09 PT

import Foundation

/// The timer engine's time source. The app uses `SystemClock`. Tests use a clock that they move by hand.
///
/// Named `TimerClock` so it does not hide Swift's own `Clock` protocol.
protocol TimerClock {
    var now: Date { get }
}

/// The real wall clock. It follows real time through sleep, so a timer that ends while the Mac sleeps is late only
/// until the engine checks again on wake.
struct SystemClock: TimerClock {
    var now: Date {
        .now
    }
}
