@testable import Domain
import Foundation
@testable import KinCore
@testable import KinStore
@testable import SyncEngine
import Testing
import TestSupport

@Suite("KinDatabase (SwiftData)")
struct KinDatabaseTests {
    @Test("Due entries come out by priority, then age")
    func priorityOrdering() async throws {
        let database = try KinDatabase.make(inMemory: true)
        let now = Fixtures.monday(hour: 10)
        _ = try await database.enqueue(.locations([Fixtures.sample()]), at: now)
        _ = try await database.enqueue(.battery(BatteryState(level: 0.5)), at: now)
        _ = try await database.enqueue(
            .sos(SOSEvent(memberID: Fixtures.child, location: nil, battery: nil, createdAt: now)),
            at: now.addingTimeInterval(5)
        )
        let due = try await database.due(at: now.addingTimeInterval(10), limit: 10)
        #expect(due.map(\.operation.kindName) == ["sos", "locations", "battery"])
    }

    @Test("Rescheduled entries are not due until their next attempt")
    func reschedule() async throws {
        let database = try KinDatabase.make(inMemory: true)
        let now = Fixtures.monday(hour: 10)
        let id = try await database.enqueue(.battery(BatteryState(level: 0.5)), at: now)
        try await database.reschedule(id, attempt: 1, nextAttemptAt: now.addingTimeInterval(60))
        #expect(try await database.due(at: now.addingTimeInterval(30), limit: 10).isEmpty)
        let later = try await database.due(at: now.addingTimeInterval(61), limit: 10)
        #expect(later.first?.attempt == 1)
        try await database.markDelivered([id])
        #expect(try await database.count() == 0)
    }

    @Test("Command ledger remembers ids")
    func ledger() async throws {
        let database = try KinDatabase.make(inMemory: true)
        let id = UUID()
        #expect(await !database.hasSeen(id))
        await database.record(id, at: .now)
        await database.record(id, at: .now) // idempotent
        #expect(await database.hasSeen(id))
    }

    @Test("Location history is pruned after the retention window")
    func retention() async throws {
        let database = try KinDatabase.make(inMemory: true)
        let now = Fixtures.monday(hour: 10)
        try await database.append([
            Fixtures.sample(at: now.addingTimeInterval(-40 * 86400)),
            Fixtures.sample(at: now.addingTimeInterval(-3600)),
        ])
        #expect(try await database.pruneHistory(olderThan: 30, now: now) == 1)
        #expect(try await database.locationHistory(since: .distantPast).count == 1)
    }
}

@Suite("SyncEngine (outbox)")
struct SyncEngineTests {
    func makeEngine(clock: TestClock = TestClock()) -> (SyncEngine, InMemoryOutbox, FakeCompanionService) {
        let outbox = InMemoryOutbox()
        let service = FakeCompanionService()
        let engine = SyncEngine(
            store: outbox,
            service: service,
            memberID: Fixtures.child,
            backoff: ExponentialBackoff(base: .seconds(2), jitter: false),
            now: clock.provider
        )
        return (engine, outbox, service)
    }

    @Test("Delivers by priority and coalesces location batches into one request")
    func priorityAndCoalescing() async {
        let (engine, outbox, service) = makeEngine()
        try? await engine.enqueue(.locations([Fixtures.sample()]))
        try? await engine.enqueue(.locations([Fixtures.sample(), Fixtures.sample()]))
        try? await engine.enqueue(.checkIn(CheckIn(memberID: Fixtures.child, kind: .imOK, createdAt: .now)))
        try? await engine.enqueue(.sos(SOSEvent(memberID: Fixtures.child, location: nil, battery: nil, createdAt: .now)))

        let report = await engine.flush()

        #expect(report.delivered == 4)
        #expect(report.remaining == 0)
        #expect(await service.callOrder == ["sos", "checkIn", "locations"])
        #expect(await service.uploadedBatches.map(\.count) == [3])
        #expect(await outbox.count() == 0)
    }

    @Test("Transient failures are retried later with backoff")
    func transientFailure() async {
        let clock = TestClock()
        let (engine, outbox, service) = makeEngine(clock: clock)
        await service.fail(with: [KinError.offline])
        try? await engine.enqueue(.battery(BatteryState(level: 0.4)))

        let first = await engine.flush()
        #expect(first.retried == 1)
        #expect(await outbox.entries.first?.attempt == 1)
        #expect(await outbox.entries.first?.nextAttemptAt == clock.now.addingTimeInterval(4))

        // Not due yet → nothing happens.
        #expect(await engine.flush().delivered == 0)
        clock.advance(by: 5)
        #expect(await engine.flush().delivered == 1)
    }

    @Test("Permanent failures are dropped so they can't block the queue")
    func permanentFailure() async {
        let (engine, outbox, service) = makeEngine()
        await service.fail(with: [KinError.notFound])
        try? await engine.enqueue(.battery(BatteryState(level: 0.4)))
        let report = await engine.flush()
        #expect(report.dropped == 1)
        #expect(await outbox.count() == 0)
    }

    @Test("Concurrent flush triggers join a single in-flight flush")
    func singleFlight() async {
        let (engine, _, service) = makeEngine()
        await service.setDelay(.milliseconds(50))
        try? await engine.enqueue(.battery(BatteryState(level: 0.4)))
        async let first = engine.flush()
        async let second = engine.flush()
        _ = await (first, second)
        #expect(await service.callOrder == ["battery"])
    }

    @Test("Companion actions are durable before they are sent")
    func actions() async throws {
        let (engine, outbox, service) = makeEngine()
        await service.fail(with: [KinError.offline])
        let sos = try await engine.sendSOS()
        #expect(sos.memberID == Fixtures.child)
        // Delivery failed, but the SOS is still safely queued.
        #expect(await outbox.count() == 1)
        _ = try await engine.requestExtraTime(.thirtyMinutes, message: "please", appName: nil)
        #expect(await waitUntil { await service.requests.count == 1 })
    }
}
