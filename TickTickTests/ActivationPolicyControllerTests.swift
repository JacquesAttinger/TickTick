// Last edited: 2026-09-24 19:09 PT

import AppKit
import Testing
@testable import TickTick

@MainActor
private final class FakeHost: ActivationHost {
    var isActive = false
    var hasOpenWindow = false
    private(set) var policies: [NSApplication.ActivationPolicy] = []
    private(set) var activationCount = 0

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        policies.append(activationPolicy)
        return true
    }

    func activateTickTick() {
        activationCount += 1
        isActive = true
    }
}

@MainActor
private final class FakeApp: FocusReturnTarget {
    var isTerminated = false
    private(set) var focusBackCount = 0

    func takeFocusBack() {
        focusBackCount += 1
    }
}

@MainActor
struct ActivationPolicyControllerTests {
    private let host = FakeHost()
    private let previous = FakeApp()
    private let controller: ActivationPolicyController

    init() {
        controller = ActivationPolicyController(host: host, workspace: nil)
        controller.rememberActiveApp(previous)
    }

    // MARK: - Popover

    @Test("The popover closes with no window open: the app in front before gets the keyboard back")
    func popoverCloseReturnsFocus() {
        host.isActive = true

        controller.popoverDidClose()

        #expect(previous.focusBackCount == 1)
    }

    @Test("The popover closes while a TickTick window is open: TickTick keeps the keyboard")
    func popoverCloseWithWindowKeepsFocus() {
        host.isActive = true
        host.hasOpenWindow = true

        controller.popoverDidClose()

        #expect(previous.focusBackCount == 0)
    }

    @Test("The popover closes because you clicked another app: nothing changes")
    func popoverCloseWhenInactiveDoesNothing() {
        host.isActive = false

        controller.popoverDidClose()

        #expect(previous.focusBackCount == 0)
    }

    @Test("The app in front before has quit: nothing changes")
    func quitAppGetsNoFocus() {
        host.isActive = true
        previous.isTerminated = true

        controller.popoverDidClose()

        #expect(previous.focusBackCount == 0)
    }

    @Test("The keyboard goes back to the app that was active last")
    func lastActiveAppWins() {
        let later = FakeApp()
        controller.rememberActiveApp(later)
        host.isActive = true

        controller.popoverDidClose()

        #expect(previous.focusBackCount == 0)
        #expect(later.focusBackCount == 1)
    }

    @Test("A mouse click activates TickTick, and no event or a key press does not")
    func clickActivates() throws {
        controller.activateForClick(nil)
        try controller.activateForClick(Self.event(.keyDown))
        #expect(host.activationCount == 0)

        try controller.activateForClick(Self.event(.leftMouseDown))
        #expect(host.activationCount == 1)
    }

    @Test("A click while TickTick is active does not activate again")
    func clickWhenActiveDoesNothing() throws {
        host.isActive = true

        try controller.activateForClick(Self.event(.leftMouseUp))

        #expect(host.activationCount == 0)
    }

    // MARK: - Windows

    @Test("A window shows: Dock icon on and TickTick active. It closes: Dock icon off")
    func windowTogglesDockIcon() {
        let window = Self.window()

        controller.windowWillShow(window)
        #expect(host.policies == [.regular])
        #expect(host.activationCount == 1)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(host.policies == [.regular, .accessory])
    }

    @Test("The Dock icon stays while a second window is open")
    func dockIconStaysForSecondWindow() {
        let first = Self.window()
        let second = Self.window()
        controller.windowWillShow(first)
        controller.windowWillShow(second)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: first)
        #expect(host.policies.last == .regular)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: second)
        #expect(host.policies.last == .accessory)
    }

    @Test("Open and close the same window 5 times: the Dock icon follows each time")
    func reopenSameWindow() {
        let window = Self.window()

        for _ in 0 ..< 5 {
            controller.windowWillShow(window)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        }

        #expect(host.policies == Array(repeating: [.regular, .accessory], count: 5).flatMap(\.self))
    }

    @Test("The last window closes: the app in front before gets the keyboard back")
    func lastWindowCloseReturnsFocus() async {
        let window = Self.window()
        controller.windowWillShow(window)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        // The check waits one main actor turn, until the window is gone.
        await Task.yield()
        await Task.yield()

        #expect(previous.focusBackCount == 1)
    }

    private static func window() -> NSWindow {
        NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    }

    private static func event(_ type: NSEvent.EventType) throws -> NSEvent {
        if type == .keyDown {
            return try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
            ))
        }
        return try #require(NSEvent.mouseEvent(
            with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }
}
