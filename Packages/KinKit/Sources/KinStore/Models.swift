import Foundation
import SwiftData

// SwiftData schema. Kept internal: nothing outside `KinStore` sees a `@Model` class, so the rest of the app only
// handles immutable, `Sendable` domain values and never trips over cross-actor `PersistentModel` access.

@Model
final class OutboxRecord {
    @Attribute(.unique) var id: UUID
    var kind: String
    var payload: Data
    var priority: Int
    var attempt: Int
    var createdAt: Date
    var nextAttemptAt: Date

    init(id: UUID, kind: String, payload: Data, priority: Int, attempt: Int, createdAt: Date, nextAttemptAt: Date) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.priority = priority
        self.attempt = attempt
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
    }
}

@Model
final class SeenCommandRecord {
    @Attribute(.unique) var id: UUID
    var seenAt: Date

    init(id: UUID, seenAt: Date) {
        self.id = id
        self.seenAt = seenAt
    }
}

@Model
final class LocationRecord {
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var speed: Double?
    var isStationary: Bool
    var timestamp: Date

    init(latitude: Double, longitude: Double, accuracy: Double, speed: Double?, isStationary: Bool, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.speed = speed
        self.isStationary = isStationary
        self.timestamp = timestamp
    }
}
