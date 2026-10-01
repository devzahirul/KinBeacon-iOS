@testable import DemoBackend
@testable import Domain
import Foundation
import Testing
import TestSupport

@Suite("DemoBackend")
struct DemoBackendTests {
    func backend(_ perspective: DemoBackend.Configuration.Perspective) -> DemoBackend {
        DemoBackend(configuration: .init(perspective: perspective, beat: .milliseconds(20), spontaneousEvents: false))
    }

    @Test("Seeds a family with an open safety alert")
    func seed() async throws {
        let demo = backend(.parent)
        var iterator = demo.snapshots().makeAsyncIterator()
        let snapshot = try #require(await iterator.next())
        #expect(snapshot.children.map(\.name) == ["Emma", "Lucas"])
        #expect(snapshot.openAlerts.map(\.kind) == [.locationPermissionOff])
        #expect(snapshot.activeModes[DemoData.emmaID]?.kind == .school)
    }

    @Test("Approving a request pauses the active mode")
    func approve() async throws {
        let demo = backend(.parent)
        let request = TimeRequest(childID: DemoData.emmaID, option: .fifteenMinutes, createdAt: .now)
        try await demo.submit(request)
        try await demo.submit(request) // idempotent retry
        #expect(try await demo.pendingRequests().count == 1)
        let answered = try await demo.respond(to: request.id, approve: true)
        guard case .approved = answered.status else {
            Issue.record("Expected approval, got \(answered.status)")
            return
        }
        #expect(try await demo.pendingRequests().isEmpty)
        try await demo.refresh()
        var iterator = demo.snapshots().makeAsyncIterator()
        let snapshot = try #require(await iterator.next())
        #expect(snapshot.activeModes[DemoData.emmaID]?.isPaused(at: .now) == true)
    }

    @Test("A remote fix resolves the permission alert")
    func fixPermissions() async throws {
        let demo = backend(.parent)
        try await demo.send(.fixPermissions(.location), to: DemoData.lucasID)
        let resolved = await waitUntil {
            var iterator = demo.snapshots().makeAsyncIterator()
            return await iterator.next()?.openAlerts.isEmpty == true
        }
        #expect(resolved)
    }

    @Test("Saving controls bumps the revision")
    func saveControls() async throws {
        let demo = backend(.parent)
        let controls = try await demo.controls(for: DemoData.emmaID)
        let saved = try await demo.save(controls)
        #expect(saved.revision == controls.revision + 1)
    }

    @Test("The simulated parent answers a child's request")
    func childPerspective() async throws {
        let demo = backend(.child)
        var updates = demo.timeRequestUpdates().makeAsyncIterator()
        try await demo.submit(TimeRequest(childID: DemoData.emmaID, option: .thirtyMinutes, createdAt: .now))
        let update = try #require(await updates.next())
        if case .approved = update.status {} else {
            Issue.record("Expected approval")
        }
    }

    @Test("Screen-time data is deterministic")
    func deterministic() {
        let date = Fixtures.monday(hour: 20)
        let first = ScreenTimeGenerator.summary(
            member: DemoData.emmaID,
            range: .week,
            anchor: date,
            now: date,
            limit: 180,
            calendar: Fixtures.calendar
        )
        let second = ScreenTimeGenerator.summary(
            member: DemoData.emmaID,
            range: .week,
            anchor: date,
            now: date,
            limit: 180,
            calendar: Fixtures.calendar
        )
        #expect(first == second)
        #expect(first.buckets.count == 7)
        #expect(first.totalMinutes > 0)
    }
}
