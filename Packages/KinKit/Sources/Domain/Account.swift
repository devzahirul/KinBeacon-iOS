public import Foundation

/// Which family this device belongs to, and as whom.
public struct FamilyMembership: Hashable, Codable, Sendable {
    public var memberID: MemberID
    public var familyID: String
    public var role: MemberRole

    public init(memberID: MemberID, familyID: String, role: MemberRole) {
        self.memberID = memberID
        self.familyID = familyID
        self.role = role
    }
}

public enum AccountState: Equatable, Sendable {
    case signedOut
    /// A parent account exists but hasn't created (or joined) a family yet.
    case signedInWithoutFamily
    case member(FamilyMembership)
}

/// A one-time code a parent shows to pair a child's device.
public struct ChildInvite: Hashable, Sendable {
    public var code: String
    public var memberID: MemberID
    public var expiresAt: Date

    public init(code: String, memberID: MemberID, expiresAt: Date) {
        self.code = code
        self.memberID = memberID
        self.expiresAt = expiresAt
    }

    /// "482 913"
    public var formattedCode: String {
        "\(code.prefix(3)) \(code.suffix(3))"
    }
}

public struct NewChild: Hashable, Sendable {
    public var name: String
    public var age: Int?
    public var grade: Int?
    public var avatar: Avatar

    public init(name: String, age: Int?, grade: Int?, avatar: Avatar) {
        self.name = name
        self.age = age
        self.grade = grade
        self.avatar = avatar
    }
}

public enum AccountValidation {
    public static let minimumPasswordLength = 8

    public static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !trimmed.contains(" ")
    }

    public static func isValidPairingCode(_ code: String) -> Bool {
        let digits = code.filter(\.isNumber)
        return digits.count == 6 && digits.count == code.filter { !$0.isWhitespace }.count
    }
}

/// Sign-up / sign-in for parents, device pairing for children, and account deletion (App Store 5.1.1(v)).
public protocol AccountService: Sendable {
    func restore() async -> AccountState
    func signUp(name: String, email: String, password: String) async throws -> AccountState
    func signIn(email: String, password: String) async throws -> AccountState
    func createFamily(name: String, parentName: String, relationship: String?) async throws -> FamilyMembership
    /// Creates a device account if needed and redeems the parent's code.
    func pairDevice(code: String, deviceModel: String) async throws -> FamilyMembership
    func inviteChild(_ child: NewChild) async throws -> ChildInvite
    func refreshInvite(for member: MemberID) async throws -> ChildInvite
    func registerPushToken(_ token: String, sandbox: Bool) async
    func signOut() async
    func deleteAccount() async throws
}

/// Family membership management (parents only).
public protocol FamilyAdminService: Sendable {
    /// Removes a child from the family. Their device, location history, controls, requests and check-ins are
    /// deleted; the child's device shows that it is no longer in a family.
    func removeChild(_ id: MemberID) async throws
}

/// Safe places are managed by parents.
public protocol PlaceService: Sendable {
    func save(_ place: Place) async throws
    func deletePlace(_ id: PlaceID) async throws
}

/// Rebuilds "Lincoln Elementary 8:12 AM – Present" style visits from raw location history.
public enum VisitBuilder {
    /// A visit needs this many consecutive minutes inside a place to count (filters drive-bys).
    public static let minimumStay: TimeInterval = 5 * 60

    public static func visits(from samples: [LocationSample], places: [Place], now: Date) -> [PlaceVisit] {
        let evaluator = GeofenceEvaluator(places: places)
        var visits: [PlaceVisit] = []
        var current: (place: Place, start: Date, last: Date)?
        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            let place = evaluator.currentPlace(for: sample.coordinate)
            if let open = current, place?.id == open.place.id {
                current?.last = sample.timestamp
                continue
            }
            if let open = current, open.last.timeIntervalSince(open.start) >= minimumStay {
                visits.append(PlaceVisit(
                    placeName: open.place.name,
                    kind: open.place.kind,
                    arrivedAt: open.start,
                    leftAt: sample.timestamp
                ))
            }
            current = place.map { ($0, sample.timestamp, sample.timestamp) }
        }
        if let open = current, now.timeIntervalSince(open.start) >= minimumStay || open.last.timeIntervalSince(open.start) >= minimumStay {
            visits.append(PlaceVisit(placeName: open.place.name, kind: open.place.kind, arrivedAt: open.start, leftAt: nil))
        }
        return visits.reversed()
    }
}

/// The parent/child timeline is derived from the source records rather than stored twice.
public enum ActivityTimeline {
    public static func events(checkIns: [CheckIn], requests: [TimeRequest], alerts: [SafetyAlert], limit: Int) -> [ActivityEvent] {
        var events: [ActivityEvent] = checkIns.map {
            ActivityEvent(id: $0.id, memberID: $0.memberID, kind: .checkIn($0.kind, message: $0.message), timestamp: $0.createdAt)
        }
        for request in requests {
            events.append(ActivityEvent(
                memberID: request.childID,
                kind: .timeRequested(minutes: request.option.minutes),
                timestamp: request.createdAt
            ))
            switch request.status {
            case let .approved(until):
                let answeredAt = until.addingTimeInterval(-Double(request.option.minutes) * 60)
                events.append(ActivityEvent(
                    memberID: request.childID,
                    kind: .timeApproved(minutes: request.option.minutes),
                    timestamp: answeredAt
                ))
            case .denied:
                events.append(ActivityEvent(
                    memberID: request.childID,
                    kind: .timeDenied,
                    timestamp: request.createdAt.addingTimeInterval(1)
                ))
            case .pending, .expired:
                break
            }
        }
        for alert in alerts {
            switch alert.kind {
            case .sos: events.append(ActivityEvent(id: alert.id, memberID: alert.memberID, kind: .sos, timestamp: alert.createdAt))
            case .locationPermissionOff:
                events.append(ActivityEvent(
                    id: alert.id,
                    memberID: alert.memberID,
                    kind: .permissionChanged(.location, granted: false),
                    timestamp: alert.createdAt
                ))
            case .notificationsOff:
                events.append(ActivityEvent(
                    id: alert.id,
                    memberID: alert.memberID,
                    kind: .permissionChanged(.notifications, granted: false),
                    timestamp: alert.createdAt
                ))
            case .deviceProtectionOff:
                events.append(ActivityEvent(
                    id: alert.id,
                    memberID: alert.memberID,
                    kind: .permissionChanged(.screenTime, granted: false),
                    timestamp: alert.createdAt
                ))
            case .needHelp, .lowBattery:
                break
            }
        }
        return Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }
}
