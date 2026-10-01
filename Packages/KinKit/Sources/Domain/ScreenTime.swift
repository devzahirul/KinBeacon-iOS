public import Foundation

public enum ScreenTimeRange: String, Codable, Sendable, CaseIterable, Identifiable {
    case day
    case week
    case month

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        }
    }

    public var childTitle: String {
        switch self {
        case .day: String(localized: "Today")
        case .week: String(localized: "This Week")
        case .month: String(localized: "This Month")
        }
    }

    public var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

public struct AppUsage: Identifiable, Hashable, Codable, Sendable {
    public var app: AppDescriptor
    public var minutes: Int

    public var id: String {
        app.id
    }

    public init(app: AppDescriptor, minutes: Int) {
        self.app = app
        self.minutes = minutes
    }
}

/// One bar in the usage chart: an hour (day range) or a day (week/month range).
public struct UsageBucket: Identifiable, Hashable, Codable, Sendable {
    public var start: Date
    public var minutes: Int

    public var id: Date {
        start
    }

    public init(start: Date, minutes: Int) {
        self.start = start
        self.minutes = minutes
    }
}

public struct ScreenTimeSummary: Hashable, Codable, Sendable {
    public var range: ScreenTimeRange
    public var anchor: Date
    public var buckets: [UsageBucket]
    public var topApps: [AppUsage]
    public var previousTotalMinutes: Int
    public var dailyLimitMinutes: Int

    public init(
        range: ScreenTimeRange,
        anchor: Date,
        buckets: [UsageBucket],
        topApps: [AppUsage],
        previousTotalMinutes: Int,
        dailyLimitMinutes: Int
    ) {
        self.range = range
        self.anchor = anchor
        self.buckets = buckets
        self.topApps = topApps
        self.previousTotalMinutes = previousTotalMinutes
        self.dailyLimitMinutes = dailyLimitMinutes
    }

    public var totalMinutes: Int {
        buckets.reduce(0) { $0 + $1.minutes }
    }

    /// Signed change vs the previous period (-0.28 = 28 % less). `nil` when there is no baseline.
    public var change: Double? {
        guard previousTotalMinutes > 0 else { return nil }
        return Double(totalMinutes - previousTotalMinutes) / Double(previousTotalMinutes)
    }

    /// Progress toward the daily limit (day range only), clamped to 0...1 for progress bars.
    public var limitProgress: Double {
        guard dailyLimitMinutes > 0 else { return 0 }
        return min(Double(totalMinutes) / Double(dailyLimitMinutes), 1)
    }

    public var maxBucketMinutes: Int {
        buckets.map(\.minutes).max() ?? 0
    }

    /// Average per day for week/month ranges.
    public func dailyAverage(calendar: Calendar = .current) -> Int {
        guard range != .day, !buckets.isEmpty else { return totalMinutes }
        return totalMinutes / buckets.count
    }
}

public enum ScreenTimeAggregator {
    /// Rolls hourly samples up into day buckets for week/month charts.
    public static func dailyBuckets(from hourly: [UsageBucket], calendar: Calendar = .current) -> [UsageBucket] {
        let grouped = Dictionary(grouping: hourly) { calendar.startOfDay(for: $0.start) }
        return grouped
            .map { UsageBucket(start: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.start < $1.start }
    }

    /// Merges per-app usage from several days and returns the top `limit`, largest first.
    public static func topApps(_ usage: [AppUsage], limit: Int = 4) -> [AppUsage] {
        var totals: [String: AppUsage] = [:]
        for entry in usage {
            totals[entry.app.id, default: AppUsage(app: entry.app, minutes: 0)].minutes += entry.minutes
        }
        return totals.values
            .sorted { $0.minutes == $1.minutes ? $0.app.name < $1.app.name : $0.minutes > $1.minutes }
            .prefix(limit)
            .map(\.self)
    }
}

/// What the child's home screen shows.
public struct ChildDashboard: Hashable, Codable, Sendable {
    public var member: FamilyMember
    public var guardianName: String
    public var activeMode: ActiveMode?
    public var screenTimeTodayMinutes: Int
    public var dailyLimitMinutes: Int
    public var recentActivity: [ActivityEvent]
    public var isLocationSharing: Bool
    public var isConnected: Bool
    public var battery: BatteryState?

    public init(
        member: FamilyMember,
        guardianName: String,
        activeMode: ActiveMode?,
        screenTimeTodayMinutes: Int,
        dailyLimitMinutes: Int,
        recentActivity: [ActivityEvent],
        isLocationSharing: Bool,
        isConnected: Bool,
        battery: BatteryState?
    ) {
        self.member = member
        self.guardianName = guardianName
        self.activeMode = activeMode
        self.screenTimeTodayMinutes = screenTimeTodayMinutes
        self.dailyLimitMinutes = dailyLimitMinutes
        self.recentActivity = recentActivity
        self.isLocationSharing = isLocationSharing
        self.isConnected = isConnected
        self.battery = battery
    }
}
