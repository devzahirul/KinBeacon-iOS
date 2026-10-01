public import Foundation

/// Locale-aware formatting helpers. Every user-visible duration, time and relative date goes through here so the app
/// renders "1 h 26 min" in German and "15:15" on 24-hour devices without per-screen code.
public enum KinFormat {
    /// "1h 26m", "48m", "0m".
    public static func duration(_ duration: Duration) -> String {
        let total = max(0, Int(duration.timeInterval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = hours > 0 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = hours > 0 ? .dropTrailing : .default
        let components = DateComponents(hour: hours, minute: minutes)
        return formatter.string(from: components) ?? "\(hours)h \(minutes)m"
    }

    /// "3:15 PM" / "15:15".
    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar))
    }

    /// "8 min ago", "Just now".
    public static func relative(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 {
            return String(localized: "Just now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// "Today, Apr 17", "Mon, Apr 14".
    public static func dayTitle(_ date: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today, \(day)")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "72%".
    public static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}
