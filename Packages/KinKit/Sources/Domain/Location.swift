public import Foundation

/// A WGS-84 coordinate. Domain code never imports CoreLocation, so every geo rule is testable on any platform.
public struct Coordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres (haversine; < 0.5 % error at city scale — plenty for geofencing).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let haversine = sin(deltaLat / 2) * sin(deltaLat / 2) + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(haversine), sqrt(1 - haversine))
    }

    /// Linear interpolation — used by the demo route player; accurate enough over a few hundred metres.
    public func interpolated(to other: Coordinate, fraction: Double) -> Coordinate {
        let clamped = min(max(fraction, 0), 1)
        return Coordinate(
            latitude: latitude + (other.latitude - latitude) * clamped,
            longitude: longitude + (other.longitude - longitude) * clamped
        )
    }
}

public struct LocationSample: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    /// Radius of uncertainty in metres.
    public var horizontalAccuracy: Double
    public var timestamp: Date
    /// Metres per second, `nil` when unknown.
    public var speed: Double?
    public var isStationary: Bool

    public init(coordinate: Coordinate, horizontalAccuracy: Double, timestamp: Date, speed: Double? = nil, isStationary: Bool = false) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
        self.speed = speed
        self.isStationary = isStationary
    }
}

public enum PlaceKind: String, Codable, Sendable, CaseIterable {
    case home
    case school
    case park
    case other

    public var shortName: String {
        switch self {
        case .home: String(localized: "Home")
        case .school: String(localized: "School")
        case .park: String(localized: "Park")
        case .other: String(localized: "Place")
        }
    }

    public var symbol: String {
        switch self {
        case .home: "house.fill"
        case .school: "building.columns.fill"
        case .park: "tree.fill"
        case .other: "mappin"
        }
    }
}

/// A "safe place" — monitored with a circular geofence on the child's device.
public struct Place: Identifiable, Hashable, Codable, Sendable {
    public var id: PlaceID
    public var name: String
    public var kind: PlaceKind
    public var coordinate: Coordinate
    /// Geofence radius in metres. iOS delivers region events reliably only from ~100 m upward.
    public var radius: Double
    public var address: String
    public var notifiesOnArrival: Bool
    public var notifiesOnDeparture: Bool

    public init(
        id: PlaceID,
        name: String,
        kind: PlaceKind,
        coordinate: Coordinate,
        radius: Double = 150,
        address: String,
        notifiesOnArrival: Bool = true,
        notifiesOnDeparture: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.coordinate = coordinate
        self.radius = max(radius, Place.minimumRadius)
        self.address = address
        self.notifiesOnArrival = notifiesOnArrival
        self.notifiesOnDeparture = notifiesOnDeparture
    }

    /// Below this, Wi-Fi/cell positioning jitter produces false enter/exit storms.
    public static let minimumRadius = 100.0

    public func contains(_ coordinate: Coordinate, padding: Double = 0) -> Bool {
        self.coordinate.distance(to: coordinate) <= radius + padding
    }
}
