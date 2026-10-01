import Domain
import Foundation
@testable import SupabaseBackend
import Testing
import TestSupport

/// End-to-end against the real Supabase project (RLS, RPCs, Realtime). Runs only when the test host has backend
/// credentials (Config/Supabase.local.xcconfig); otherwise it is skipped, so CI without secrets stays green.
/// Every run creates a fresh family and deletes it at the end.
let integrationConfiguration = SupabaseConfiguration(infoDictionary: Bundle.main.infoDictionary)

@Suite("Supabase end-to-end", .serialized, .enabled(if: integrationConfiguration != nil))
struct SupabaseIntegrationTests {
    static let configuration = integrationConfiguration

    @Test("Parent invites, child pairs, data and commands flow both ways under RLS", .timeLimit(.minutes(2)))
    func familyRoundTrip() async throws {
        let configuration = try #require(Self.configuration)
        let runID = UUID().uuidString.prefix(8).lowercased()
        let parent = SupabaseKinBackend(configuration: configuration, storageKey: "kin.it.parent.\(runID)")
        let child = SupabaseKinBackend(configuration: configuration, storageKey: "kin.it.child.\(runID)")
        DeviceCredentials.clear()
        // Parent account + family + child invite.
        #expect(try await parent
            .signUp(name: "IT Parent", email: "it-\(runID)@test.kinbeacon.app", password: "it-\(runID)-password") == .signedInWithoutFamily)
        let parentMembership = try await parent.createFamily(name: "IT Family \(runID)", parentName: "IT Parent", relationship: "Mom")
        #expect(parentMembership.role == .parent)
        let invite = try await parent.inviteChild(NewChild(name: "Kid", age: 10, grade: 4, avatar: Avatar(emoji: "👧", palette: 0)))
        #expect(invite.code.count == 6)
        // A wrong code is rejected, the right one pairs.
        await #expect(throws: KinError.invalidPairingCode) { try await child.pairDevice(code: "000000", deviceModel: "iPhone") }
        let childMembership = try await child.pairDevice(code: invite.code, deviceModel: "iPhone")
        #expect(childMembership.memberID == invite.memberID)
        #expect(childMembership.familyID == parentMembership.familyID)
        // Realtime: the parent's feed sees the child's check-in.
        let feed = parent.events()
        let seen = SeenIDs()
        let watcher = Task {
            for await event in feed {
                if case let .checkIn(value) = event {
                    await seen.insert(value.id)
                }
            }
        }
        defer { watcher.cancel() }
        // Wait until the family Realtime channel has actually joined before producing events.
        var ready = parent.liveReadyHub.stream().makeAsyncIterator()
        #expect(await ready.next() == "family")
        // Child reports location → parent snapshot shows it at the right place.
        try await parent.save(Place(
            id: PlaceID(rawValue: UUID().uuidString.lowercased()),
            name: "School",
            kind: .school,
            coordinate: Fixtures.school.coordinate,
            address: ""
        ))
        try await child.upload(locations: [Fixtures.sample(at: Date())])
        let snapshot = try await parent.loadSnapshot()
        #expect(snapshot.status(invite.memberID)?.location != nil)
        #expect(snapshot.place(snapshot.status(invite.memberID)?.placeID)?.name == "School")
        #expect(snapshot.activeModes[invite.memberID] != nil || snapshot.children.count == 1)
        // Extra time: child asks (idempotently), parent approves, child sees the approval.
        let request = TimeRequest(childID: invite.memberID, option: .fifteenMinutes, message: "IT", createdAt: Date())
        try await child.submit(request)
        try await child.submit(request)
        #expect(try await parent.pendingRequests().map(\.id) == [request.id])
        let answered = try await parent.respond(to: request.id, approve: true)
        if case .approved = answered.status {} else {
            Issue.record("expected approval, got \(answered.status)")
        }
        #expect(try await child.timeRequests().first?.status == answered.status)
        // "Need help" check-in raises an alert for the parent and arrives on the realtime feed.
        let checkIn = CheckIn(memberID: invite.memberID, kind: .needHelp, message: "IT", createdAt: Date())
        try await child.submit(checkIn)
        #expect(try await parent.loadSnapshot().openAlerts.contains { $0.kind == .needHelp })
        let received = await waitUntil(timeout: .seconds(15)) { await seen.contains(checkIn.id) }
        #expect(received, "check-in should arrive over Realtime")
        // Remote command: parent sends, child fetches and acknowledges.
        try await parent.send(.locateNow, to: invite.memberID)
        let pending = try await child.pendingCommands()
        #expect(pending.map(\.action).contains(.locateNow))
        for command in pending {
            try await child.acknowledge(command.id)
        }
        #expect(try await child.pendingCommands().isEmpty)
        // Permission regression → alert; recovery → resolved.
        var degraded = PermissionHealthReport.healthy
        degraded.states[.location] = .denied
        try await child.report(permissions: .healthy)
        try await child.report(permissions: degraded)
        #expect(try await parent.loadSnapshot().openAlerts.contains { $0.kind == .locationPermissionOff })
        try await child.report(permissions: .healthy)
        #expect(try await !parent.loadSnapshot().openAlerts.contains { $0.kind == .locationPermissionOff })
        // The parent removes the child: the child's device is no longer in a family.
        try await parent.removeChild(invite.memberID)
        #expect(try await parent.loadSnapshot().member(invite.memberID) == nil)
        await #expect(throws: KinError.notFound) { _ = try await child.dashboard() }

        // Clean up: the child device leaves, then the last parent deletes the whole family.
        try await child.deleteAccount()
        try await parent.deleteAccount()
        #expect(await parent.restore() == .signedOut)
    }
}

actor SeenIDs {
    private var ids: Set<UUID> = []
    func insert(_ id: UUID) {
        ids.insert(id)
    }

    func contains(_ id: UUID) -> Bool {
        ids.contains(id)
    }
}
