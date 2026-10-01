public import Domain
public import Foundation
public import SwiftData
import KinCore

/// The on-device database: outbox, replay-protection ledger and local location history.
///
/// `@ModelActor` gives the actor its own `ModelContext` bound to a background serial executor, so inserts and
/// fetches never run on the main thread (no frame drops while 500 queued fixes are flushed after a subway ride).
/// Only `Sendable` domain values cross the actor boundary.
@ModelActor
public actor KinDatabase {
    public static func make(inMemory: Bool = false, url: URL? = nil) throws -> KinDatabase {
        let schema = Schema([OutboxRecord.self, SeenCommandRecord.self, LocationRecord.self])
        let configuration = if inMemory {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            ModelConfiguration(schema: schema, url: url ?? AppConstants.sharedContainerURL.appending(path: "KinBeacon.store"))
        }
        let container = try ModelContainer(for: schema, configurations: configuration)
        return KinDatabase(modelContainer: container)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: Location history

    public func append(_ samples: [LocationSample]) throws {
        for sample in samples {
            modelContext.insert(LocationRecord(
                latitude: sample.coordinate.latitude,
                longitude: sample.coordinate.longitude,
                accuracy: sample.horizontalAccuracy,
                speed: sample.speed,
                isStationary: sample.isStationary,
                timestamp: sample.timestamp
            ))
        }
        try modelContext.save()
    }

    public func locationHistory(since date: Date, limit: Int = 500) throws -> [LocationSample] {
        var descriptor = FetchDescriptor<LocationRecord>(
            predicate: #Predicate { $0.timestamp >= date },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { record in
            LocationSample(
                coordinate: Coordinate(latitude: record.latitude, longitude: record.longitude),
                horizontalAccuracy: record.accuracy,
                timestamp: record.timestamp,
                speed: record.speed,
                isStationary: record.isStationary
            )
        }
    }

    /// Retention: location history older than `days` is deleted (data minimisation — App Store guideline 5.1.2).
    @discardableResult
    public func pruneHistory(olderThan days: Int, now: Date) throws -> Int {
        let cutoff = now.addingTimeInterval(-Double(days) * 86400)
        let stale = try modelContext.fetchCount(FetchDescriptor<LocationRecord>(predicate: #Predicate { $0.timestamp < cutoff }))
        try modelContext.delete(model: LocationRecord.self, where: #Predicate { $0.timestamp < cutoff })
        let oldCommands = now.addingTimeInterval(-7 * 86400)
        try modelContext.delete(model: SeenCommandRecord.self, where: #Predicate { $0.seenAt < oldCommands })
        try modelContext.save()
        return stale
    }
}

// MARK: - OutboxStore

extension KinDatabase: OutboxStore {
    public func enqueue(_ operation: OutboxOperation, at date: Date) throws -> UUID {
        let id = UUID()
        let record = try OutboxRecord(
            id: id,
            kind: operation.kindName,
            payload: Self.encoder.encode(operation),
            priority: operation.priority,
            attempt: 0,
            createdAt: date,
            nextAttemptAt: date
        )
        modelContext.insert(record)
        try modelContext.save()
        return id
    }

    public func due(at date: Date, limit: Int) throws -> [OutboxEntry] {
        var descriptor = FetchDescriptor<OutboxRecord>(
            predicate: #Predicate { $0.nextAttemptAt <= date },
            sortBy: [SortDescriptor(\.priority), SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).compactMap { record in
            do {
                let operation = try Self.decoder.decode(OutboxOperation.self, from: record.payload)
                return OutboxEntry(
                    id: record.id,
                    operation: operation,
                    attempt: record.attempt,
                    createdAt: record.createdAt,
                    nextAttemptAt: record.nextAttemptAt
                )
            } catch {
                // A payload from an older app version we can no longer decode: drop it instead of blocking the queue.
                Log.storage.error("Dropping undecodable outbox entry \(record.kind, privacy: .public)")
                modelContext.delete(record)
                return nil
            }
        }
    }

    public func markDelivered(_ ids: [UUID]) throws {
        try modelContext.delete(model: OutboxRecord.self, where: #Predicate { ids.contains($0.id) })
        try modelContext.save()
    }

    public func reschedule(_ id: UUID, attempt: Int, nextAttemptAt: Date) throws {
        guard let record = try record(id) else { return }
        record.attempt = attempt
        record.nextAttemptAt = nextAttemptAt
        try modelContext.save()
    }

    public func drop(_ id: UUID) throws {
        try markDelivered([id])
    }

    public func count() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<OutboxRecord>())
    }

    private func record(_ id: UUID) throws -> OutboxRecord? {
        var descriptor = FetchDescriptor<OutboxRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

// MARK: - CommandLedger

extension KinDatabase: CommandLedger {
    public func hasSeen(_ id: UUID) -> Bool {
        var descriptor = FetchDescriptor<SeenCommandRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    public func record(_ id: UUID, at date: Date) {
        guard !hasSeen(id) else { return }
        modelContext.insert(SeenCommandRecord(id: id, seenAt: date))
        do {
            try modelContext.save()
        } catch {
            Log.storage.error("Failed to persist command id: \(error.localizedDescription, privacy: .public)")
        }
    }
}
