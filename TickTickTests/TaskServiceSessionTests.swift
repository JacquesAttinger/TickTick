// Last edited: 2026-09-24 15:14 PT

import Foundation
import SwiftData
import Testing
@testable import TickTick

/// The `TaskService` operations that the timer engine uses: sessions, lookups by ID, and the estimate.
@MainActor
struct TaskServiceSessionTests {
    private let store: ModelStore
    private let service: TaskService
    private let inbox: Note
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        store = try ModelStore(inMemory: true)
        service = TaskService(context: store.context)
        inbox = try store.bootstrapInbox()
    }

    @Test("startSession opens a saved session on the task")
    func startSessionOpensASession() {
        let task = service.createTask(title: "Write report", in: inbox)

        let session = service.startSession(for: task, plannedSeconds: 1500, at: start)

        #expect(session.task === task)
        #expect(task.sessions?.contains { $0 === session } == true)
        #expect(session.startedAt == start)
        #expect(session.plannedSeconds == 1500)
        #expect(session.activeSeconds == 0)
        #expect(session.endedAt == nil)
        #expect(session.outcome == nil)
        #expect(!store.context.hasChanges)
    }

    @Test("closeSession saves the end, the times, and the outcome")
    func closeSessionRecordsTheRun() {
        let task = service.createTask(title: "Write report", in: inbox)
        let session = service.startSession(for: task, plannedSeconds: 1500, at: start)
        let end = start.addingTimeInterval(2000)

        service.closeSession(session, endedAt: end, activeSeconds: 1800, plannedSeconds: 1800, outcome: .done)

        #expect(session.endedAt == end)
        #expect(session.activeSeconds == 1800)
        #expect(session.plannedSeconds == 1800)
        #expect(session.outcome == .done)
        #expect(!store.context.hasChanges)
    }

    @Test("A closed session shows up in actualSeconds")
    func closedSessionCountsAsActualTime() {
        let task = service.createTask(title: "Write report", in: inbox)
        let first = service.startSession(for: task, plannedSeconds: 60, at: start)
        service.closeSession(first, endedAt: start, activeSeconds: 60, plannedSeconds: 60, outcome: .stopped)
        let second = service.startSession(for: task, plannedSeconds: 300, at: start)

        #expect(service.actualSeconds(for: task) == 60)

        service.closeSession(second, endedAt: start, activeSeconds: 330, plannedSeconds: 300, outcome: .done)

        #expect(service.actualSeconds(for: task) == 390)
    }

    @Test("session(withID:) finds a session, and returns nil for an unknown ID")
    func sessionLookupByID() {
        let task = service.createTask(title: "Write report", in: inbox)
        let session = service.startSession(for: task, plannedSeconds: 60, at: start)

        #expect(service.session(withID: session.id) === session)
        #expect(service.session(withID: UUID()) == nil)
    }

    @Test("task(withID:) finds a task, and returns nil after the task is deleted")
    func taskLookupByID() {
        let task = service.createTask(title: "Write report", in: inbox)
        let id = task.id

        #expect(service.task(withID: id) === task)

        service.deleteTask(task)

        #expect(service.task(withID: id) == nil)
    }

    @Test("setEstimate sets and clears the estimate")
    func setEstimateSetsAndClears() {
        let task = service.createTask(title: "Write report", in: inbox)

        service.setEstimate(2700, for: task)
        #expect(task.estimateSeconds == 2700)
        #expect(!store.context.hasChanges)

        service.setEstimate(nil, for: task)
        #expect(task.estimateSeconds == nil)
    }
}
