import Domain
import Foundation

// Wire models for the `kinbeacon` schema (snake_case columns). Kept internal: features only ever see Domain types.

struct MemberRow: Codable, Sendable {
    var id: String
    var familyID: String
    var userID: String?
    var role: String
    var name: String
    var relationship: String?
    var grade: Int?
    var age: Int?
    var avatarEmoji: String
    var avatarPalette: Int
    var deviceModel: String?

    enum CodingKeys: String, CodingKey {
        case id, role, name, relationship, grade, age
        case familyID = "family_id", userID = "user_id", avatarEmoji = "avatar_emoji"
        case avatarPalette = "avatar_palette", deviceModel = "device_model"
    }

    var domain: FamilyMember {
        FamilyMember(
            id: MemberID(rawValue: id),
            name: name,
            role: MemberRole(rawValue: role) ?? .child,
            avatar: Avatar(emoji: avatarEmoji, palette: avatarPalette),
            relationship: relationship,
            grade: grade,
            age: age,
            deviceModel: deviceModel
        )
    }
}

struct FamilyRow: Codable, Sendable {
    var id: String
    var name: String
}

struct PlaceRow: Codable, Sendable {
    var id: String
    var familyID: String
    var name: String
    var kind: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var address: String
    var notifiesOnArrival: Bool
    var notifiesOnDeparture: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, kind, latitude, longitude, radius, address
        case familyID = "family_id", notifiesOnArrival = "notifies_on_arrival", notifiesOnDeparture = "notifies_on_departure"
    }

    init(_ place: Place, familyID: String) {
        id = place.id.rawValue
        self.familyID = familyID
        name = place.name
        kind = place.kind.rawValue
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        radius = place.radius
        address = place.address
        notifiesOnArrival = place.notifiesOnArrival
        notifiesOnDeparture = place.notifiesOnDeparture
    }

    var domain: Place {
        Place(
            id: PlaceID(rawValue: id),
            name: name,
            kind: PlaceKind(rawValue: kind) ?? .other,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            radius: radius,
            address: address,
            notifiesOnArrival: notifiesOnArrival,
            notifiesOnDeparture: notifiesOnDeparture
        )
    }
}

struct StatusRow: Codable, Sendable {
    var memberID: String
    var familyID: String
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?
    var speed: Double?
    var isStationary: Bool?
    var locationAt: Date?
    var placeID: String?
    var batteryLevel: Double?
    var batteryCharging: Bool?
    var permissions: [String: String]?
    var lastSeen: Date?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, accuracy, speed, permissions
        case memberID = "member_id", familyID = "family_id", isStationary = "is_stationary", locationAt = "location_at"
        case placeID = "place_id", batteryLevel = "battery_level", batteryCharging = "battery_charging", lastSeen = "last_seen"
    }

    func domain(addressFor place: Place?) -> MemberStatus {
        var location: LocationSample?
        if let latitude, let longitude {
            location = LocationSample(
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                horizontalAccuracy: accuracy ?? 50,
                timestamp: locationAt ?? lastSeen ?? .distantPast,
                speed: speed,
                isStationary: isStationary ?? false
            )
        }
        let states = (permissions ?? [:]).reduce(into: [PermissionKind: PermissionState]()) { result, pair in
            if let kind = PermissionKind(rawValue: pair.key), let state = PermissionState(rawValue: pair.value) {
                result[kind] = state
            }
        }
        return MemberStatus(
            memberID: MemberID(rawValue: memberID),
            location: location,
            placeID: placeID.map(PlaceID.init(rawValue:)),
            address: place?.address,
            battery: batteryLevel.map { BatteryState(level: $0, isCharging: batteryCharging ?? false) },
            isOnline: true,
            lastSeen: lastSeen ?? .distantPast,
            permissions: states.isEmpty ? .healthy : PermissionHealthReport(states: states)
        )
    }
}

/// Partial upserts: only non-nil columns are sent, so a battery update never wipes the location (PostgREST
/// `resolution=merge-duplicates` only touches columns present in the payload).
struct StatusPatch: Encodable, Sendable {
    var memberID: String
    var familyID: String
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?
    var speed: Double?
    var isStationary: Bool?
    var locationAt: Date?
    var placeID: String?
    var batteryLevel: Double?
    var batteryCharging: Bool?
    var permissions: [String: String]?
    var lastSeen = Date()

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, accuracy, speed, permissions
        case memberID = "member_id", familyID = "family_id", isStationary = "is_stationary", locationAt = "location_at"
        case placeID = "place_id", batteryLevel = "battery_level", batteryCharging = "battery_charging", lastSeen = "last_seen"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memberID, forKey: .memberID)
        try container.encode(familyID, forKey: .familyID)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(accuracy, forKey: .accuracy)
        try container.encodeIfPresent(speed, forKey: .speed)
        try container.encodeIfPresent(isStationary, forKey: .isStationary)
        try container.encodeIfPresent(locationAt, forKey: .locationAt)
        try container.encodeIfPresent(placeID, forKey: .placeID)
        try container.encodeIfPresent(batteryLevel, forKey: .batteryLevel)
        try container.encodeIfPresent(batteryCharging, forKey: .batteryCharging)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encode(lastSeen, forKey: .lastSeen)
    }
}

struct SampleRow: Codable, Sendable {
    var memberID: String
    var familyID: String
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var speed: Double?
    var isStationary: Bool
    var recordedAt: Date

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, accuracy, speed
        case memberID = "member_id", familyID = "family_id", isStationary = "is_stationary", recordedAt = "recorded_at"
    }

    var domain: LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            horizontalAccuracy: accuracy,
            timestamp: recordedAt,
            speed: speed,
            isStationary: isStationary
        )
    }
}

struct ControlsRow: Codable, Sendable {
    var memberID: String
    var familyID: String?
    var revision: Int?
    var config: ControlsConfiguration

    enum CodingKeys: String, CodingKey {
        case revision, config
        case memberID = "member_id", familyID = "family_id"
    }

    init(memberID: String, familyID: String?, revision: Int?, config: ControlsConfiguration) {
        self.memberID = memberID
        self.familyID = familyID
        self.revision = revision
        self.config = config
    }

    /// Tolerant decoding: an empty or older-format controls document must never take the child's app down — it falls
    /// back to the safe defaults (School Mode on school days) until a parent saves new controls.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memberID = try container.decode(String.self, forKey: .memberID)
        familyID = try container.decodeIfPresent(String.self, forKey: .familyID)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision)
        config = (try? container.decode(ControlsConfiguration.self, forKey: .config))
            ?? .defaults(for: MemberID(rawValue: memberID))
    }

    var domain: ControlsConfiguration {
        var configuration = config
        configuration.childID = MemberID(rawValue: memberID)
        configuration.revision = revision ?? configuration.revision
        return configuration
    }
}

struct ControlsUpdate: Encodable, Sendable {
    var config: ControlsConfiguration
}

struct RequestRow: Codable, Sendable {
    var id: UUID
    var familyID: String
    var memberID: String
    var minutes: Int
    var message: String?
    var appName: String?
    var status: String
    var approvedUntil: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, minutes, message, status
        case familyID = "family_id", memberID = "member_id", appName = "app_name"
        case approvedUntil = "approved_until", createdAt = "created_at"
    }

    init(_ request: TimeRequest, familyID: String) {
        id = request.id
        self.familyID = familyID
        memberID = request.childID.rawValue
        minutes = request.option.minutes
        message = request.message
        appName = request.appName
        status = "pending"
        createdAt = request.createdAt
    }

    var domain: TimeRequest {
        let state: TimeRequestStatus = switch status {
        case "approved": .approved(until: approvedUntil ?? createdAt)
        case "denied": .denied
        case "expired": .expired
        default: .pending
        }
        return TimeRequest(
            id: id,
            childID: MemberID(rawValue: memberID),
            option: ExtraTimeOption(rawValue: minutes) ?? .fifteenMinutes,
            message: message,
            appName: appName,
            createdAt: createdAt,
            status: state
        )
    }
}

struct CheckInRow: Codable, Sendable {
    var id: UUID
    var familyID: String
    var memberID: String
    var kind: String
    var message: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, message, latitude, longitude
        case familyID = "family_id", memberID = "member_id", createdAt = "created_at"
    }

    init(_ checkIn: CheckIn, familyID: String) {
        id = checkIn.id
        self.familyID = familyID
        memberID = checkIn.memberID.rawValue
        kind = checkIn.kind.rawValue
        message = checkIn.message
        latitude = checkIn.location?.coordinate.latitude
        longitude = checkIn.location?.coordinate.longitude
        createdAt = checkIn.createdAt
    }

    var domain: CheckIn {
        CheckIn(
            id: id,
            memberID: MemberID(rawValue: memberID),
            kind: CheckInKind(rawValue: kind) ?? .imOK,
            message: message,
            location: latitude.flatMap { lat in
                longitude.map { LocationSample(
                    coordinate: Coordinate(latitude: lat, longitude: $0),
                    horizontalAccuracy: 50,
                    timestamp: createdAt
                ) }
            },
            createdAt: createdAt
        )
    }
}

struct AlertRow: Codable, Sendable {
    var id: UUID
    var familyID: String
    var memberID: String
    var kind: String
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, latitude, longitude
        case familyID = "family_id", memberID = "member_id", createdAt = "created_at", resolvedAt = "resolved_at"
    }

    init(_ alert: SafetyAlert, familyID: String, location: LocationSample? = nil) {
        id = alert.id
        self.familyID = familyID
        memberID = alert.memberID.rawValue
        kind = alert.kind.rawValue
        latitude = location?.coordinate.latitude
        longitude = location?.coordinate.longitude
        createdAt = alert.createdAt
        resolvedAt = alert.resolvedAt
    }

    var domain: SafetyAlert? {
        guard let kind = SafetyAlert.Kind(rawValue: kind) else { return nil }
        return SafetyAlert(id: id, memberID: MemberID(rawValue: memberID), kind: kind, createdAt: createdAt, resolvedAt: resolvedAt)
    }
}

struct ResolvePatch: Encodable, Sendable {
    var resolvedAt = Date()

    enum CodingKeys: String, CodingKey { case resolvedAt = "resolved_at" }
}

struct CommandRow: Codable, Sendable {
    var id: UUID?
    var familyID: String
    var target: String
    var action: RemoteCommand.Action
    var issuedBy: String?
    var issuedAt: Date?
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, target, action
        case familyID = "family_id", issuedBy = "issued_by", issuedAt = "issued_at", expiresAt = "expires_at"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(familyID, forKey: .familyID)
        try container.encode(target, forKey: .target)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(issuedBy, forKey: .issuedBy)
    }

    var domain: RemoteCommand? {
        guard let id else { return nil }
        let issued = issuedAt ?? Date()
        return RemoteCommand(
            id: id,
            target: MemberID(rawValue: target),
            action: action,
            issuedAt: issued,
            expiresAt: expiresAt ?? issued.addingTimeInterval(3600)
        )
    }
}

struct DeliveredPatch: Encodable, Sendable {
    var deliveredAt = Date()

    enum CodingKeys: String, CodingKey { case deliveredAt = "delivered_at" }
}

struct DeviceTokenRow: Encodable, Sendable {
    var userID: String
    var token: String
    var environment: String
    var updatedAt = Date()

    enum CodingKeys: String, CodingKey {
        case token, environment
        case userID = "user_id", updatedAt = "updated_at"
    }
}

struct InviteRow: Decodable, Sendable {
    var code: String
    var memberID: String?
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case code
        case memberID = "member_id", expiresAt = "expires_at"
    }
}
