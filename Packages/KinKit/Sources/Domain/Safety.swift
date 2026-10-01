public import Foundation
import KinCore

// MARK: - Permissions

/// The OS permissions a child device needs for the family's safety features to work.
public enum PermissionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case location
    case notifications
    case backgroundRefresh
    case screenTime

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .location: String(localized: "Location access")
        case .notifications: String(localized: "Notifications")
        case .backgroundRefresh: String(localized: "Background refresh")
        case .screenTime: String(localized: "Device protection")
        }
    }

    public var symbol: String {
        switch self {
        case .location: "location.fill"
        case .notifications: "bell.fill"
        case .backgroundRefresh: "arrow.triangle.2.circlepath"
        case .screenTime: "iphone"
        }
    }

    /// Why we ask — shown in onboarding and on the Help screen (App Review guideline 5.1.1 requires a clear purpose).
    public var rationale: String {
        switch self {
        case .location: String(
                localized: "Lets your family see where you are and get arrival alerts. Choose “Always” so it works when the app is closed."
            )
        case .notifications: String(localized: "So you get replies to check-ins and extra-time requests right away.")
        case .backgroundRefresh: String(localized: "Keeps your status up to date without opening the app.")
        case .screenTime: String(localized: "Lets your family set School Mode and app limits on this device.")
        }
    }
}

public enum PermissionState: String, Codable, Sendable {
    case granted
    /// Granted but degraded — e.g. location "While Using" or approximate only.
    case limited
    case denied
    case notDetermined

    public var isSatisfied: Bool {
        self == .granted
    }

    public var label: String {
        switch self {
        case .granted: String(localized: "On")
        case .limited: String(localized: "Limited")
        case .denied: String(localized: "Off")
        case .notDetermined: String(localized: "Not set")
        }
    }
}

public struct PermissionHealthReport: Hashable, Codable, Sendable {
    public var states: [PermissionKind: PermissionState]

    public init(states: [PermissionKind: PermissionState]) {
        self.states = states
    }

    public static let healthy =
        PermissionHealthReport(states: Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, .granted) }))

    public subscript(kind: PermissionKind) -> PermissionState {
        states[kind] ?? .notDetermined
    }

    public var issues: [PermissionKind] {
        PermissionKind.allCases.filter { !self[$0].isSatisfied }
    }

    public var isHealthy: Bool {
        issues.isEmpty
    }
}

public enum PermissionHealthEvaluator {
    /// Permissions that went from satisfied to unsatisfied — the signal for "Location permission turned off".
    public static func regressions(from old: PermissionHealthReport, to new: PermissionHealthReport) -> [PermissionKind] {
        PermissionKind.allCases.filter { old[$0].isSatisfied && !new[$0].isSatisfied }
    }

    public static func recoveries(from old: PermissionHealthReport, to new: PermissionHealthReport) -> [PermissionKind] {
        PermissionKind.allCases.filter { !old[$0].isSatisfied && new[$0].isSatisfied }
    }

    /// Alerts for the parent when a child's device regresses. Background refresh is reported in the health card
    /// but is not alert-worthy on its own (Low Power Mode turns it off temporarily).
    public static func alerts(
        memberID: MemberID,
        from old: PermissionHealthReport,
        to new: PermissionHealthReport,
        now: Date
    ) -> [SafetyAlert] {
        regressions(from: old, to: new).compactMap { kind in
            let alertKind: SafetyAlert.Kind? = switch kind {
            case .location: .locationPermissionOff
            case .notifications: .notificationsOff
            case .screenTime: .deviceProtectionOff
            case .backgroundRefresh: nil
            }
            return alertKind.map { SafetyAlert(memberID: memberID, kind: $0, createdAt: now) }
        }
    }
}

// MARK: - Alerts

public struct SafetyAlert: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case locationPermissionOff
        case notificationsOff
        case deviceProtectionOff
        case sos
        case needHelp
        case lowBattery
    }

    public enum Severity: Int, Codable, Sendable, Comparable {
        case info, warning, critical
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var id: UUID
    public var memberID: MemberID
    public var kind: Kind
    public var createdAt: Date
    public var resolvedAt: Date?

    public init(id: UUID = UUID(), memberID: MemberID, kind: Kind, createdAt: Date, resolvedAt: Date? = nil) {
        self.id = id
        self.memberID = memberID
        self.kind = kind
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }

    public var isResolved: Bool {
        resolvedAt != nil
    }

    public var severity: Severity {
        switch kind {
        case .sos, .needHelp, .locationPermissionOff, .deviceProtectionOff: .critical
        case .notificationsOff, .lowBattery: .warning
        }
    }

    public var title: String {
        switch kind {
        case .locationPermissionOff: String(localized: "Location permission turned off")
        case .notificationsOff: String(localized: "Notifications turned off")
        case .deviceProtectionOff: String(localized: "Screen Time access removed")
        case .sos: String(localized: "SOS alert")
        case .needHelp: String(localized: "Asked for help")
        case .lowBattery: String(localized: "Battery is low")
        }
    }

    public func summary(childName: String) -> String {
        switch kind {
        case .locationPermissionOff: String(localized: "\(childName)’s device is no longer sharing location.")
        case .notificationsOff: String(localized: "\(childName) won’t see replies to check-ins or requests.")
        case .deviceProtectionOff: String(localized: "School Mode and app limits can’t be enforced on \(childName)’s device.")
        case .sos: String(localized: "\(childName) triggered SOS. Their live location is shared with you.")
        case .needHelp: String(localized: "\(childName) checked in with “Need help”.")
        case .lowBattery: String(localized: "\(childName)’s battery is running low. Location may stop updating.")
        }
    }

    public func explanation(childName: String) -> String {
        switch kind {
        case .locationPermissionOff:
            String(
                localized: "We can’t see \(childName)’s real-time location until location permission is turned back on. This may affect safety features like arrival alerts and location history."
            )
        case .notificationsOff:
            String(localized: "\(childName) can still use the app, but won’t be notified when you answer a request or ask for a check-in.")
        case .deviceProtectionOff:
            String(
                localized: """
                Screen Time access was removed in Settings. School Mode, \
                Bedtime and app limits are paused until it’s granted again.
                """
            )
        case .sos, .needHelp:
            String(localized: "Call \(childName) now. Their location keeps updating every few seconds while the alert is open.")
        case .lowBattery:
            String(localized: "Location updates slow down to save battery. Ask \(childName) to charge their device.")
        }
    }

    /// Whether a remote "fix it" nudge can be sent to the child's device.
    public var isFixableRemotely: Bool {
        switch kind {
        case .locationPermissionOff, .notificationsOff, .deviceProtectionOff: true
        case .sos, .needHelp, .lowBattery: false
        }
    }
}

// MARK: - Activity timeline

public struct ActivityEvent: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        case checkIn(CheckInKind, message: String?)
        case locationShared
        case arrived(placeName: String)
        case left(placeName: String)
        case modeStarted(ControlModeKind, until: Date)
        case modeEnded(ControlModeKind)
        case timeRequested(minutes: Int)
        case timeApproved(minutes: Int)
        case timeDenied
        case sos
        case permissionChanged(PermissionKind, granted: Bool)
    }

    public var id: UUID
    public var memberID: MemberID
    public var kind: Kind
    public var timestamp: Date

    public init(id: UUID = UUID(), memberID: MemberID, kind: Kind, timestamp: Date) {
        self.id = id
        self.memberID = memberID
        self.kind = kind
        self.timestamp = timestamp
    }

    public var title: String {
        switch kind {
        case .checkIn: String(localized: "Check-in sent")
        case .locationShared: String(localized: "Location shared")
        case let .arrived(place): String(localized: "Arrived at \(place)")
        case let .left(place): String(localized: "Left \(place)")
        case let .modeStarted(mode, _): String(localized: "\(mode.modeTitle) started")
        case let .modeEnded(mode): String(localized: "\(mode.modeTitle) ended")
        case let .timeRequested(minutes): String(localized: "Asked for \(minutes) more minutes")
        case let .timeApproved(minutes): String(localized: "\(minutes) extra minutes approved")
        case .timeDenied: String(localized: "Extra time declined")
        case .sos: String(localized: "SOS sent")
        case let .permissionChanged(kind, granted):
            if granted {
                String(localized: "\(kind.title) turned on")
            } else {
                String(localized: "\(kind.title) turned off")
            }
        }
    }

    public var subtitle: String {
        switch kind {
        case let .checkIn(kind, message): message.map { "“\($0)”" } ?? "“\(kind.title)”"
        case .locationShared: String(localized: "Shared successfully")
        case .arrived, .left: String(localized: "Safe place alert")
        case let .modeStarted(_, until): String(localized: "Apps limited until \(KinFormat.time(until))")
        case .modeEnded: String(localized: "All apps available")
        case .timeRequested: String(localized: "Waiting for a reply")
        case .timeApproved: String(localized: "Apps unlocked for a bit")
        case .timeDenied: String(localized: "Maybe later")
        case .sos: String(localized: "Family notified with live location")
        case .permissionChanged: String(localized: "Device settings changed")
        }
    }

    public var symbol: String {
        switch kind {
        case .checkIn: "bubble.left.fill"
        case .locationShared: "location.fill"
        case .arrived: "figure.walk.arrival"
        case .left: "figure.walk.departure"
        case .modeStarted, .modeEnded: "graduationcap.fill"
        case .timeRequested, .timeApproved, .timeDenied: "clock.fill"
        case .sos: "exclamationmark.triangle.fill"
        case .permissionChanged: "gearshape.fill"
        }
    }
}
