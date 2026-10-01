public import Domain
public import Foundation

/// The fictional family used by the demo backend, previews, UI tests and App Store screenshots.
public enum DemoData {
    public static let parentID: MemberID = "member-sarah"
    public static let emmaID: MemberID = "member-emma"
    public static let lucasID: MemberID = "member-lucas"

    public static let sarah = FamilyMember(
        id: parentID,
        name: "Sarah",
        role: .parent,
        avatar: Avatar(emoji: "👩🏻", palette: 3),
        relationship: "Mom"
    )
    public static let emma = FamilyMember(
        id: emmaID, name: "Emma", role: .child, avatar: Avatar(emoji: "👧🏼", palette: 0), grade: 4, age: 10, deviceModel: "iPhone"
    )
    public static let lucas = FamilyMember(
        id: lucasID, name: "Lucas", role: .child, avatar: Avatar(emoji: "👦🏽", palette: 1), grade: 2, age: 8, deviceModel: "iPad"
    )

    public static let home = Place(
        id: "place-home", name: "Home", kind: .home,
        coordinate: Coordinate(latitude: 37.7566, longitude: -122.4302), radius: 120, address: "48 Maple Street"
    )
    public static let school = Place(
        id: "place-school", name: "Lincoln Elementary School", kind: .school,
        coordinate: Coordinate(latitude: 37.7631, longitude: -122.4214), radius: 180, address: "123 School Ave"
    )
    public static let park = Place(
        id: "place-park", name: "Riverside Park", kind: .park,
        coordinate: Coordinate(latitude: 37.7598, longitude: -122.4271), radius: 200, address: "Riverside Dr"
    )
    public static let downtown = Coordinate(latitude: 37.7712, longitude: -122.4143)

    public static let places = [home, school, park]

    // MARK: App catalogue (stand-ins for opaque ApplicationTokens)

    public static let phone = AppDescriptor(id: "com.apple.mobilephone", name: "Phone", symbol: "phone.fill", palette: 4)
    public static let messages = AppDescriptor(
        id: "com.apple.MobileSMS",
        name: "Messages",
        symbol: "message.fill",
        palette: 4,
        category: .chat
    )
    public static let camera = AppDescriptor(id: "com.apple.camera", name: "Camera", symbol: "camera.fill", palette: 6)
    public static let classroom = AppDescriptor(id: "com.google.classroom", name: "Google Classroom", symbol: "studentdesk", palette: 7)
    public static let notability = AppDescriptor(
        id: "com.gingerlabs.Notability",
        name: "Notability",
        symbol: "pencil.and.scribble",
        palette: 0
    )
    public static let safari = AppDescriptor(id: "com.apple.mobilesafari", name: "Safari", symbol: "safari.fill", palette: 0)
    public static let youtube = AppDescriptor(
        id: "com.google.ios.youtube",
        name: "YouTube",
        symbol: "play.rectangle.fill",
        palette: 5,
        category: .videoStreaming
    )
    public static let roblox = AppDescriptor(
        id: "com.roblox.robloxmobile",
        name: "Roblox",
        symbol: "cube.fill",
        palette: 6,
        category: .games
    )
    public static let chrome = AppDescriptor(id: "com.google.chrome.ios", name: "Chrome", symbol: "globe", palette: 7)
    public static let instagram = AppDescriptor(
        id: "com.burbn.instagram",
        name: "Instagram",
        symbol: "camera.aperture",
        palette: 2,
        category: .socialMedia
    )
    public static let minecraft = AppDescriptor(
        id: "com.mojang.minecraftpe",
        name: "Minecraft",
        symbol: "square.grid.3x3.fill",
        palette: 4,
        category: .games
    )
    public static let khan = AppDescriptor(
        id: "org.khanacademy.Khan-Academy",
        name: "Khan Academy",
        symbol: "graduationcap.fill",
        palette: 1
    )
    public static let duolingo = AppDescriptor(id: "com.duolingo.DuolingoMobile", name: "Duolingo", symbol: "bird.fill", palette: 4)

    public static let appCatalog = [
        phone,
        messages,
        camera,
        classroom,
        notability,
        safari,
        youtube,
        roblox,
        chrome,
        instagram,
        minecraft,
        khan,
        duolingo,
    ]

    public static func controls(for child: MemberID, now: Date, calendar: Calendar = .current) -> ControlsConfiguration {
        var configuration = ControlsConfiguration.defaults(for: child)
        if var school = configuration.mode(.school) {
            school.allowedApps = AppSelection(apps: [phone, messages, camera, classroom])
            school.schedule = demoSchoolSchedule(now: now, calendar: calendar)
            configuration.update(school)
        }
        if var homework = configuration.mode(.homework) {
            homework.allowedApps = AppSelection(apps: [classroom, khan, notability])
            configuration.update(homework)
        }
        configuration.alwaysAllowed = AppSelection(apps: [phone, messages])
        configuration.appLimits = [AppLimit(app: youtube, dailyMinutes: 60), AppLimit(app: roblox, dailyMinutes: 45)]
        configuration.downtime = WeeklySchedule(start: TimeOfDay(hour: 20, minute: 30), end: TimeOfDay(hour: 7), days: Weekday.everyDay)
        return configuration
    }

    /// Real school hours (Mon–Fri 08:00–15:15) when the demo is opened during them; otherwise a window around "now"
    /// so a reviewer opening the demo in the evening still sees School Mode in action. Demo-only behaviour.
    static func demoSchoolSchedule(now: Date, calendar: Calendar) -> WeeklySchedule {
        let real = WeeklySchedule(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 15, minute: 15), days: Weekday.schoolDays)
        if real.isActive(at: now, calendar: calendar) {
            return real
        }
        let hour = calendar.component(.hour, from: now)
        let start = TimeOfDay(hour: max(hour - 1, 0))
        let end = TimeOfDay(hour: min(hour + 3, 23), minute: 15)
        return WeeklySchedule(start: start, end: end, days: Weekday.schoolDays.union([Weekday(now, calendar: calendar)]))
    }
}

/// Deterministic pseudo-random numbers (SplitMix64) so generated screen-time data is stable across launches and in
/// UI tests. `String.hashValue` is seeded per process, hence the FNV-1a seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum ScreenTimeGenerator {
    /// Hourly usage for one day; hours after `now` are zero.
    static func hourly(member: MemberID, day: Date, now: Date, calendar: Calendar) -> [UsageBucket] {
        let start = calendar.startOfDay(for: day)
        var rng = SeededGenerator(seed: "\(member.rawValue)-\(Int(start.timeIntervalSince1970))")
        return (0 ..< 24).compactMap { hour in
            guard let bucketStart = calendar.date(byAdding: .hour, value: hour, to: start) else { return nil }
            guard bucketStart <= now else { return UsageBucket(start: bucketStart, minutes: 0) }
            let range: ClosedRange<Int> = switch hour {
            case 0 ..< 7: 0 ... 0
            case 7: 0 ... 8
            case 8 ..< 15: 0 ... 9
            case 15 ..< 18: 8 ... 34
            case 18 ..< 21: 4 ... 26
            case 21: 0 ... 6
            default: 0 ... 0
            }
            var minutes = Int.random(in: range, using: &rng)
            // The current hour is only partly over.
            if calendar.isDate(bucketStart, equalTo: now, toGranularity: .hour) {
                minutes = minutes * calendar.component(.minute, from: now) / 60
            }
            return UsageBucket(start: bucketStart, minutes: minutes)
        }
    }

    static func topApps(member: MemberID, totalMinutes: Int, day: Date, calendar: Calendar) -> [AppUsage] {
        let weights: [(AppDescriptor, Double)] = [
            (DemoData.youtube, 0.42), (DemoData.roblox, 0.23), (DemoData.chrome, 0.2), (DemoData.messages, 0.13),
        ]
        return weights.map { AppUsage(app: $0.0, minutes: Int(Double(totalMinutes) * $0.1)) }
    }

    // Mirrors ActivityService's signature plus demo-only inputs.
    // swiftlint:disable:next function_parameter_count
    static func summary(
        member: MemberID,
        range: ScreenTimeRange,
        anchor: Date,
        now: Date,
        limit: Int,
        calendar: Calendar
    ) -> ScreenTimeSummary {
        func days(endingAt end: Date, count: Int) -> [Date] {
            (0 ..< count).compactMap { calendar.date(byAdding: .day, value: -$0, to: end) }.reversed()
        }
        let dayCount = switch range {
        case .day: 1
        case .week: 7
        case .month: calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
        }
        let buckets: [UsageBucket]
        let previous: Int
        if range == .day {
            buckets = hourly(member: member, day: anchor, now: now, calendar: calendar)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: anchor) ?? anchor
            // Compare like with like: yesterday up to the same time of day.
            let cutoff = calendar.date(byAdding: .day, value: -1, to: min(now, anchor.addingTimeInterval(86400))) ?? now
            previous = hourly(member: member, day: yesterday, now: cutoff, calendar: calendar).reduce(0) { $0 + $1.minutes } * 13 / 10
        } else {
            let allHours = days(endingAt: anchor, count: dayCount).flatMap { Self.hourly(
                member: member,
                day: $0,
                now: now,
                calendar: calendar
            ) }
            buckets = ScreenTimeAggregator.dailyBuckets(from: allHours, calendar: calendar)
            let previousEnd = calendar.date(byAdding: .day, value: -dayCount, to: anchor) ?? anchor
            previous = days(endingAt: previousEnd, count: dayCount)
                .flatMap { Self.hourly(member: member, day: $0, now: now, calendar: calendar) }
                .reduce(0) { $0 + $1.minutes }
        }
        let total = buckets.reduce(0) { $0 + $1.minutes }
        return ScreenTimeSummary(
            range: range,
            anchor: anchor,
            buckets: buckets,
            topApps: topApps(member: member, totalMinutes: total, day: anchor, calendar: calendar),
            previousTotalMinutes: previous,
            dailyLimitMinutes: limit
        )
    }
}
