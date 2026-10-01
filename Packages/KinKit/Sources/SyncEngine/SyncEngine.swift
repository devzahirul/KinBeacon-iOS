public import Domain
public import Foundation
public import KinCore

/// Outbox-based delivery of everything a child device reports.
///
/// Every action is first written to SwiftData (`OutboxStore`) and only then sent. That gives:
/// • **Durability** — an "I'm OK" typed in a lift is delivered when the signal comes back, even if iOS kills the app.
/// • **Ordering by importance** — SOS jumps the queue; location batches go last and are coalesced into one request.
/// • **Battery** — one radio wake-up per flush instead of one per fix.
/// • **Exactly-once effect** — retries reuse the entity UUID as `Idempotency-Key`.
///
/// `flush()` is single-flight: concurrent triggers (foreground, connectivity regained, BG task, new action) join the
/// in-progress flush instead of racing it.
public actor SyncEngine {
    public struct FlushReport: Equatable, Sendable {
        public var delivered: Int
        public var retried: Int
        public var dropped: Int
        public var remaining: Int
    }

    public static let maxAttempts = 12

    private let store: any OutboxStore
    private let service: any CompanionService
    private let memberID: MemberID
    private let backoff: ExponentialBackoff
    private let now: @Sendable () -> Date
    private let currentLocation: @Sendable () async -> LocationSample?
    private let currentBattery: @Sendable () async -> BatteryState?
    private var inFlight: Task<FlushReport, Never>?
    private var hasPendingTrigger = false

    public init(
        store: any OutboxStore,
        service: any CompanionService,
        memberID: MemberID,
        backoff: ExponentialBackoff = ExponentialBackoff(),
        now: @escaping @Sendable () -> Date = { Date() },
        currentLocation: @escaping @Sendable () async -> LocationSample? = { nil },
        currentBattery: @escaping @Sendable () async -> BatteryState? = { nil }
    ) {
        self.store = store
        self.service = service
        self.memberID = memberID
        self.backoff = backoff
        self.now = now
        self.currentLocation = currentLocation
        self.currentBattery = currentBattery
    }

    // MARK: Enqueue

    public func enqueue(_ operation: OutboxOperation) async throws {
        _ = try await store.enqueue(operation, at: now())
        Log.sync.debug("Queued \(operation.kindName, privacy: .public)")
    }

    // MARK: Flush

    @discardableResult
    public func flush() async -> FlushReport {
        if let inFlight {
            // Someone queued work while we were sending: run once more afterwards so it isn't stranded.
            hasPendingTrigger = true
            return await inFlight.value
        }
        let task = Task { await self.drain() }
        inFlight = task
        var report = await task.value
        inFlight = nil
        if hasPendingTrigger {
            hasPendingTrigger = false
            report = await flush()
        }
        return report
    }

    private func drain() async -> FlushReport {
        let signpost = Perf.begin("sync.flush")
        defer { Perf.end("sync.flush", signpost) }
        var report = FlushReport(delivered: 0, retried: 0, dropped: 0, remaining: 0)
        let due: [OutboxEntry]
        do {
            due = try await store.due(at: now(), limit: 100)
        } catch {
            Log.sync.error("Outbox read failed: \(error.localizedDescription, privacy: .public)")
            return report
        }

        // Coalesce all queued location batches into one upload.
        let locationEntries = due.filter {
            if case .locations = $0.operation {
                true
            } else {
                false
            }
        }
        let others = due.filter { entry in !locationEntries.contains { $0.id == entry.id } }

        for entry in others {
            if Task.isCancelled {
                break
            }
            await deliver([entry], operation: entry.operation, report: &report)
        }
        if !locationEntries.isEmpty, !Task.isCancelled {
            let samples = locationEntries.flatMap { entry -> [LocationSample] in
                if case let .locations(samples) = entry.operation {
                    samples
                } else {
                    []
                }
            }
            await deliver(locationEntries, operation: .locations(samples), report: &report)
        }
        report.remaining = await (try? store.count()) ?? 0
        Log.sync
            .info("Flush delivered=\(report.delivered) retried=\(report.retried) dropped=\(report.dropped) remaining=\(report.remaining)")
        return report
    }

    private func deliver(_ entries: [OutboxEntry], operation: OutboxOperation, report: inout FlushReport) async {
        let ids = entries.map(\.id)
        do {
            try await send(operation)
            try await store.markDelivered(ids)
            report.delivered += entries.count
        } catch let error as KinError where !error.isTransient {
            // 4xx: the server will never accept it — retrying would block the queue forever.
            Log.sync.error("Dropping \(operation.kindName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            try? await store.markDelivered(ids)
            report.dropped += entries.count
        } catch {
            for entry in entries {
                let attempt = entry.attempt + 1
                if attempt >= Self.maxAttempts, entry.operation.priority > 0 {
                    try? await store.drop(entry.id)
                    report.dropped += 1
                } else {
                    let next = now().addingTimeInterval(backoff.delay(forAttempt: attempt).timeInterval)
                    try? await store.reschedule(entry.id, attempt: attempt, nextAttemptAt: next)
                    report.retried += 1
                }
            }
        }
    }

    private func send(_ operation: OutboxOperation) async throws {
        switch operation {
        case let .locations(samples): try await service.upload(locations: samples)
        case let .checkIn(checkIn): try await service.submit(checkIn)
        case let .timeRequest(request): try await service.submit(request)
        case let .sos(event): try await service.triggerSOS(event)
        case let .permissions(report): try await service.report(permissions: report)
        case let .battery(battery): try await service.report(battery: battery)
        }
    }
}

// MARK: - CompanionActions

extension SyncEngine: CompanionActions {
    public func sendCheckIn(_ kind: CheckInKind, message: String?) async throws -> CheckIn {
        let checkIn = await CheckIn(memberID: memberID, kind: kind, message: message, location: currentLocation(), createdAt: now())
        try await enqueue(.checkIn(checkIn))
        Task { await self.flush() }
        return checkIn
    }

    public func requestExtraTime(_ option: ExtraTimeOption, message: String?, appName: String?) async throws -> TimeRequest {
        let request = TimeRequest(childID: memberID, option: option, message: message, appName: appName, createdAt: now())
        try await enqueue(.timeRequest(request))
        Task { await self.flush() }
        return request
    }

    /// SOS is queued (durable) *and* flushed immediately on its own priority lane.
    public func sendSOS() async throws -> SOSEvent {
        let event = await SOSEvent(memberID: memberID, location: currentLocation(), battery: currentBattery(), createdAt: now())
        try await enqueue(.sos(event))
        await flush()
        return event
    }
}
