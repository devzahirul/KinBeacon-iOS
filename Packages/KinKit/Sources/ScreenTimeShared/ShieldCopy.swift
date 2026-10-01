public import Domain
public import Foundation
import KinCore

/// The text on the system shield ("Instagram is unavailable right now"). Pure so it is unit-tested and shared
/// verbatim by the ShieldConfiguration extension and the in-app preview.
public struct ShieldContent: Hashable, Sendable {
    public var title: String
    public var subtitle: String
    public var primaryButton: String?
    public var secondaryButton: String

    public init(title: String, subtitle: String, primaryButton: String?, secondaryButton: String) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButton = primaryButton
        self.secondaryButton = secondaryButton
    }
}

public enum ShieldCopy {
    public static func content(appName: String?, policy: SharedPolicy?, now: Date, calendar: Calendar = .current) -> ShieldContent {
        let name = appName ?? String(localized: "This app")
        let title = String(localized: "\(name) is unavailable right now")
        guard let mode = policy?.activeMode(at: now, calendar: calendar) else {
            return ShieldContent(
                title: title,
                subtitle: String(localized: "This app has reached its limit for today."),
                primaryButton: nil,
                secondaryButton: String(localized: "Close")
            )
        }
        let until = KinFormat.time(mode.until, calendar: calendar)
        return ShieldContent(
            title: title,
            subtitle: String(localized: "\(mode.kind.modeTitle) is active until \(until).\nThis app is limited to help you stay focused."),
            primaryButton: String(localized: "Request \(ExtraTimeOption.fifteenMinutes.minutes) min"),
            secondaryButton: String(localized: "Close")
        )
    }
}

/// Naming scheme for `DeviceActivityName` / `ManagedSettingsStore.Name`, shared by the app and the extensions.
///
/// One activity per (mode, weekday) because `DeviceActivitySchedule` repeats daily or on a single `weekday`
/// component — and iOS caps an app at 20 monitored activities, so 3 modes × 7 days = 21 would overflow.
/// `ScreenTimeKit` therefore collapses an every-day schedule into ONE daily activity (see `ActivityPlan`).
public enum ActivityNames {
    public static let extraTime = "kin.grant.extraTime"
    public static let maximumMonitoredActivities = 20

    public static func mode(_ kind: ControlModeKind, weekday: Weekday?) -> String {
        if let weekday {
            "kin.mode.\(kind.rawValue).\(weekday.rawValue)"
        } else {
            "kin.mode.\(kind.rawValue).daily"
        }
    }

    public static func modeKind(fromActivity name: String) -> ControlModeKind? {
        let parts = name.split(separator: ".")
        guard parts.count == 4, parts[0] == "kin", parts[1] == "mode" else { return nil }
        return ControlModeKind(rawValue: String(parts[2]))
    }

    public static func store(for kind: ControlModeKind) -> String {
        "kin.store.\(kind.rawValue)"
    }
}

/// The set of DeviceActivity schedules needed to enforce a configuration.
public struct ActivityPlan: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public var name: String
        public var mode: ControlModeKind
        public var weekday: Weekday?
        public var start: TimeOfDay
        public var end: TimeOfDay
    }

    public var entries: [Entry]

    public init(configuration: ControlsConfiguration) {
        entries = configuration.modes.filter(\.isEnabled).flatMap { mode -> [Entry] in
            let schedule = mode.schedule
            if schedule.days == Weekday.everyDay {
                return [Entry(
                    name: ActivityNames.mode(mode.kind, weekday: nil),
                    mode: mode.kind,
                    weekday: nil,
                    start: schedule.start,
                    end: schedule.end
                )]
            }
            return schedule.days.sorted().map { day in
                Entry(
                    name: ActivityNames.mode(mode.kind, weekday: day),
                    mode: mode.kind,
                    weekday: day,
                    start: schedule.start,
                    end: schedule.end
                )
            }
        }
    }

    /// Leaves one slot free for the extra-time activity.
    public var fitsSystemLimit: Bool {
        entries.count < ActivityNames.maximumMonitoredActivities
    }
}
