import Domain
import Foundation
import KinCore
import KinStore

/// Opens SwiftData off the main thread and in parallel with the first frame. Callers that need the database before
/// it is ready simply await it — no one blocks launch on `ModelContainer` creation.
actor DeferredDatabase: OutboxStore, CommandLedger {
    private let opening: Task<KinDatabase, Never>

    init(inMemory: Bool) {
        opening = Task.detached(priority: .utility) {
            let signpost = Perf.begin("storage.open")
            defer { Perf.end("storage.open", signpost) }
            do {
                return try KinDatabase.make(inMemory: inMemory)
            } catch {
                // A corrupt store must never brick the safety features: fall back to memory and report.
                Log.storage.fault("Opening the store failed, using in-memory: \(error.localizedDescription, privacy: .public)")
                // swiftlint:disable:next force_try
                return try! KinDatabase.make(inMemory: true)
            }
        }
    }

    var database: KinDatabase {
        get async { await opening.value }
    }

    func enqueue(_ operation: OutboxOperation, at date: Date) async throws -> UUID {
        try await database.enqueue(operation, at: date)
    }

    func due(at date: Date, limit: Int) async throws -> [OutboxEntry] {
        try await database.due(at: date, limit: limit)
    }

    func markDelivered(_ ids: [UUID]) async throws {
        try await database.markDelivered(ids)
    }

    func reschedule(_ id: UUID, attempt: Int, nextAttemptAt: Date) async throws {
        try await database.reschedule(id, attempt: attempt, nextAttemptAt: nextAttemptAt)
    }

    func drop(_ id: UUID) async throws {
        try await database.drop(id)
    }

    func count() async throws -> Int {
        try await database.count()
    }

    func hasSeen(_ id: UUID) async -> Bool {
        await database.hasSeen(id)
    }

    func record(_ id: UUID, at date: Date) async {
        await database.record(id, at: date)
    }
}
