public import Foundation

/// Extra-time options offered to the child. 15 minutes is the floor on purpose: `DeviceActivitySchedule` rejects
/// monitoring intervals shorter than 15 minutes (`intervalTooShort`), so a "5 min" option could never be enforced.
public enum ExtraTimeOption: Int, Codable, Sendable, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    public var id: Int {
        rawValue
    }

    public var minutes: Int {
        rawValue
    }

    public var title: String {
        switch self {
        case .fifteenMinutes: String(localized: "15 min")
        case .thirtyMinutes: String(localized: "30 min")
        case .oneHour: String(localized: "1 hour")
        }
    }
}

public enum TimeRequestStatus: Hashable, Codable, Sendable {
    case pending
    case approved(until: Date)
    case denied
    case expired

    public var isFinal: Bool {
        self != .pending
    }
}

public struct TimeRequest: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var childID: MemberID
    public var option: ExtraTimeOption
    public var message: String?
    /// The app the child was blocked from, when the request came from the shield ("Request 15 min").
    public var appName: String?
    public var createdAt: Date
    public var status: TimeRequestStatus

    public init(
        id: UUID = UUID(),
        childID: MemberID,
        option: ExtraTimeOption,
        message: String? = nil,
        appName: String? = nil,
        createdAt: Date,
        status: TimeRequestStatus = .pending
    ) {
        self.id = id
        self.childID = childID
        self.option = option
        self.message = message
        self.appName = appName
        self.createdAt = createdAt
        self.status = status
    }
}

/// A parent-approved window during which shields are lifted.
public struct ExtraTimeGrant: Hashable, Codable, Sendable {
    public var requestID: UUID
    public var startsAt: Date
    public var endsAt: Date

    public init(requestID: UUID, startsAt: Date, minutes: Int) {
        self.requestID = requestID
        self.startsAt = startsAt
        endsAt = startsAt.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func isActive(at date: Date) -> Bool {
        date >= startsAt && date < endsAt
    }
}

public enum TimeRequestPolicy {
    public static let maxMessageLength = 200
    /// Pending requests expire so a parent never approves time for a moment that has already passed.
    public static let pendingLifetime: TimeInterval = 30 * 60
    /// Anti-spam: at most this many requests per rolling hour.
    public static let maxRequestsPerHour = 3

    public enum Violation: Error, Equatable, Sendable {
        case messageTooLong
        case alreadyPending
        case tooManyRequests(retryAfter: Date)
        case noActiveMode
    }

    /// Trims the message and drops it when empty, so "   " never reaches the parent.
    public static func normalizedMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxMessageLength))
    }

    public static func validate(message: String, history: [TimeRequest], activeMode: ActiveMode?, now: Date) -> Violation? {
        if message.count > maxMessageLength {
            return .messageTooLong
        }
        if activeMode == nil {
            return .noActiveMode
        }
        if history.contains(where: { $0.status == .pending && now.timeIntervalSince($0.createdAt) < pendingLifetime }) {
            return .alreadyPending
        }
        let recent = history
            .filter { now.timeIntervalSince($0.createdAt) < 3600 }
            .sorted { $0.createdAt < $1.createdAt }
        if recent.count >= maxRequestsPerHour, let oldest = recent.first {
            return .tooManyRequests(retryAfter: oldest.createdAt.addingTimeInterval(3600))
        }
        return nil
    }

    /// Applies the expiry rule to a request read from storage or the network.
    public static func resolveExpiry(_ request: TimeRequest, now: Date) -> TimeRequest {
        guard request.status == .pending, now.timeIntervalSince(request.createdAt) >= pendingLifetime else { return request }
        var copy = request
        copy.status = .expired
        return copy
    }
}

public enum CheckInKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case imOK
    case pickedUp
    case onMyWay
    case needHelp

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .imOK: String(localized: "I'm OK")
        case .pickedUp: String(localized: "Picked up")
        case .onMyWay: String(localized: "On my way")
        case .needHelp: String(localized: "Need help")
        }
    }

    public var subtitle: String {
        switch self {
        case .imOK: String(localized: "Everything's good")
        case .pickedUp: String(localized: "On my way home")
        case .onMyWay: String(localized: "Almost there")
        case .needHelp: String(localized: "I need support")
        }
    }

    public var symbol: String {
        switch self {
        case .imOK: "face.smiling.inverse"
        case .pickedUp: "car.fill"
        case .onMyWay: "mappin.circle.fill"
        case .needHelp: "heart.fill"
        }
    }

    /// "Need help" is delivered as a time-sensitive notification that breaks through Focus.
    public var isUrgent: Bool {
        self == .needHelp
    }
}

public struct CheckIn: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var memberID: MemberID
    public var kind: CheckInKind
    public var message: String?
    public var location: LocationSample?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        memberID: MemberID,
        kind: CheckInKind,
        message: String? = nil,
        location: LocationSample? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.memberID = memberID
        self.kind = kind
        self.message = message
        self.location = location
        self.createdAt = createdAt
    }
}

public struct SOSEvent: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var memberID: MemberID
    public var location: LocationSample?
    public var battery: BatteryState?
    public var createdAt: Date

    public init(id: UUID = UUID(), memberID: MemberID, location: LocationSample?, battery: BatteryState?, createdAt: Date) {
        self.id = id
        self.memberID = memberID
        self.location = location
        self.battery = battery
        self.createdAt = createdAt
    }
}
