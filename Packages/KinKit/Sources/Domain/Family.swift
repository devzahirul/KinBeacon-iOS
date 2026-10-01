public import Foundation

/// Strongly typed identifiers: a `MemberID` can never be passed where a `PlaceID` is expected.
public struct MemberID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public struct PlaceID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public enum MemberRole: String, Codable, Sendable, CaseIterable {
    case parent
    case child
}

/// A deterministic, offline avatar: an emoji on a palette gradient. No remote images means no network on the
/// map's critical rendering path and nothing to cache.
public struct Avatar: Hashable, Codable, Sendable {
    public var emoji: String
    public var palette: Int

    public init(emoji: String, palette: Int) {
        self.emoji = emoji
        self.palette = palette
    }
}

public struct FamilyMember: Identifiable, Hashable, Codable, Sendable {
    public var id: MemberID
    public var name: String
    public var role: MemberRole
    public var avatar: Avatar
    /// Display label shown under the name for parents ("Mom") — children show grade + age instead.
    public var relationship: String?
    public var grade: Int?
    public var age: Int?
    public var deviceModel: String?

    public init(
        id: MemberID,
        name: String,
        role: MemberRole,
        avatar: Avatar,
        relationship: String? = nil,
        grade: Int? = nil,
        age: Int? = nil,
        deviceModel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.avatar = avatar
        self.relationship = relationship
        self.grade = grade
        self.age = age
        self.deviceModel = deviceModel
    }

    public var displayName: String {
        relationship ?? name
    }

    /// "4th Grade · 10 years old"
    public var subtitle: String {
        var parts: [String] = []
        if let grade {
            parts.append(Self.ordinalGrade(grade))
        }
        if let age {
            parts.append(String(localized: "\(age) years old"))
        }
        if parts.isEmpty, let relationship {
            parts.append(relationship)
        }
        return parts.joined(separator: " · ")
    }

    static func ordinalGrade(_ grade: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let ordinal = formatter.string(from: NSNumber(value: grade)) ?? "\(grade)"
        return String(localized: "\(ordinal) Grade")
    }
}

public struct BatteryState: Hashable, Codable, Sendable {
    public var level: Double
    public var isCharging: Bool

    public init(level: Double, isCharging: Bool = false) {
        self.level = min(max(level, 0), 1)
        self.isCharging = isCharging
    }

    public var isLow: Bool {
        level <= 0.2 && !isCharging
    }
}

/// Everything the parent sees about one member at a point in time.
public struct MemberStatus: Hashable, Codable, Sendable {
    public var memberID: MemberID
    public var location: LocationSample?
    public var placeID: PlaceID?
    public var address: String?
    public var battery: BatteryState?
    public var isOnline: Bool
    public var lastSeen: Date
    public var permissions: PermissionHealthReport

    public init(
        memberID: MemberID,
        location: LocationSample? = nil,
        placeID: PlaceID? = nil,
        address: String? = nil,
        battery: BatteryState? = nil,
        isOnline: Bool = true,
        lastSeen: Date,
        permissions: PermissionHealthReport = .healthy
    ) {
        self.memberID = memberID
        self.location = location
        self.placeID = placeID
        self.address = address
        self.battery = battery
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.permissions = permissions
    }
}

/// The parent's whole world in one immutable value. Screens derive from it; nothing mutates it in place.
public struct FamilySnapshot: Hashable, Codable, Sendable {
    public var familyName: String
    public var members: [FamilyMember]
    public var statuses: [MemberID: MemberStatus]
    public var places: [Place]
    public var activeModes: [MemberID: ActiveMode]
    public var openAlerts: [SafetyAlert]
    public var generatedAt: Date

    public init(
        familyName: String,
        members: [FamilyMember],
        statuses: [MemberID: MemberStatus],
        places: [Place],
        activeModes: [MemberID: ActiveMode] = [:],
        openAlerts: [SafetyAlert] = [],
        generatedAt: Date
    ) {
        self.familyName = familyName
        self.members = members
        self.statuses = statuses
        self.places = places
        self.activeModes = activeModes
        self.openAlerts = openAlerts
        self.generatedAt = generatedAt
    }

    public var children: [FamilyMember] {
        members.filter { $0.role == .child }
    }

    public func member(_ id: MemberID) -> FamilyMember? {
        members.first { $0.id == id }
    }

    public func status(_ id: MemberID) -> MemberStatus? {
        statuses[id]
    }

    public func place(_ id: PlaceID?) -> Place? {
        id.flatMap { id in places.first { $0.id == id } }
    }

    /// "At Lincoln Elementary School" / "Downtown" / "Location unavailable".
    public func locationTitle(for id: MemberID) -> String {
        guard let status = statuses[id] else { return String(localized: "Location unavailable") }
        if let place = place(status.placeID) {
            return String(localized: "At \(place.name)")
        }
        if let address = status.address {
            return address
        }
        return status.location == nil ? String(localized: "Location unavailable") : String(localized: "On the move")
    }

    /// Short label for the map pin: "At School", "At Home", "Downtown".
    public func pinLabel(for id: MemberID) -> String {
        guard let status = statuses[id] else { return "" }
        if let place = place(status.placeID) {
            return String(localized: "At \(place.kind.shortName)")
        }
        return status.address ?? ""
    }

    public func alerts(for id: MemberID) -> [SafetyAlert] {
        openAlerts.filter { $0.memberID == id }
    }
}
