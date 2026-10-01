public import Foundation

/// Wall-clock time without a date. Stored as minutes since midnight so it round-trips through Codable, App Group
/// storage and `DeviceActivitySchedule` `DateComponents` without time-zone drift.
public struct TimeOfDay: Hashable, Codable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public init(minutesSinceMidnight: Int) {
        let wrapped = ((minutesSinceMidnight % 1440) + 1440) % 1440
        self.init(hour: wrapped / 60, minute: wrapped % 60)
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    public var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    public func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// `Calendar` weekday numbering (Sunday = 1) so conversion to `DateComponents.weekday` is the identity.
public enum Weekday: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var id: Int {
        rawValue
    }

    public static let schoolDays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    public static let everyDay = Set(Weekday.allCases)

    /// Display order respects the user's locale (Monday-first in most of the world, Sunday-first in the US).
    public static func ordered(calendar: Calendar = .current) -> [Weekday] {
        let first = calendar.firstWeekday
        return (0 ..< 7).compactMap { Weekday(rawValue: (first - 1 + $0) % 7 + 1) }
    }

    public init(_ date: Date, calendar: Calendar = .current) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }

    public var previous: Weekday {
        Weekday(rawValue: rawValue == 1 ? 7 : rawValue - 1) ?? .saturday
    }

    public func shortName(calendar: Calendar = .current) -> String {
        calendar.shortWeekdaySymbols[rawValue - 1]
    }

    public func veryShortName(calendar: Calendar = .current) -> String {
        calendar.veryShortWeekdaySymbols[rawValue - 1]
    }

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A repeating weekly window, e.g. school hours (Mon–Fri 08:00–15:15) or bedtime (every day 21:00–07:00).
///
/// Windows that cross midnight belong to the weekday they *start* on: Friday bedtime 21:00–07:00 is active on
/// Saturday at 06:00, but not on Monday at 06:00 if Sunday is excluded.
public struct WeeklySchedule: Hashable, Codable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var days: Set<Weekday>

    public init(start: TimeOfDay, end: TimeOfDay, days: Set<Weekday>) {
        self.start = start
        self.end = end
        self.days = days
    }

    public var spansMidnight: Bool {
        end <= start
    }

    /// Window length in minutes (always > 0; a start == end schedule means a full 24 h).
    public var durationMinutes: Int {
        let raw = end.minutesSinceMidnight - start.minutesSinceMidnight
        return raw > 0 ? raw : raw + 1440
    }

    public func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        activeInterval(containing: date, calendar: calendar) != nil
    }

    /// The concrete occurrence of this window that contains `date`, if any.
    public func activeInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: date)
        // An occurrence that started yesterday can still be running (overnight windows).
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            guard days.contains(Weekday(day, calendar: calendar)) else { continue }
            let startDate = start.date(on: day, calendar: calendar)
            guard let endDate = calendar.date(byAdding: .minute, value: durationMinutes, to: startDate) else { continue }
            if date >= startDate, date < endDate {
                return DateInterval(start: startDate, end: endDate)
            }
        }
        return nil
    }

    /// The next time this window opens strictly after `date` (looks one week ahead).
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: date)
        for dayOffset in 0 ... 7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
                  days.contains(Weekday(day, calendar: calendar)) else { continue }
            let candidate = start.date(on: day, calendar: calendar)
            if candidate > date {
                return candidate
            }
        }
        return nil
    }
}
