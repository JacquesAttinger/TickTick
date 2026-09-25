// Last edited: 2026-09-24 16:43 PT

import Foundation
import Testing
@testable import TickTick

struct CustomExtendEntryTests {
    @Test("A typed duration gives its seconds", arguments: [
        ("2", 120),
        ("2m", 120),
        (" 90 min ", 5400),
        ("1h30", 5400),
        ("1:30", 5400),
    ] as [(String, TimeInterval)])
    func validEntry(text: String, seconds: TimeInterval) {
        let entry = CustomExtendEntry(text: text)

        #expect(entry.seconds == seconds)
        #expect(!entry.isInvalid)
    }

    @Test("Text that is not a duration is invalid", arguments: ["abc", "0", "2x", "25h"])
    func invalidEntry(text: String) {
        let entry = CustomExtendEntry(text: text)

        #expect(entry.seconds == nil)
        #expect(entry.isInvalid)
    }

    @Test("An empty or blank field is not an error yet", arguments: ["", "   "])
    func emptyEntry(text: String) {
        let entry = CustomExtendEntry(text: text)

        #expect(entry.seconds == nil)
        #expect(!entry.isInvalid)
    }
}
