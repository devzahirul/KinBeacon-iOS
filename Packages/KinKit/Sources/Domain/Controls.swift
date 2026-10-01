public import Foundation

public enum ControlModeKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case school
    case homework
    case bedtime

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .school: String(localized: "School")
        case .homework: String(localized: "Homework")
        case .bedtime: String(localized: "Bedtime")
        }
    }

    public var modeTitle: String {
        String(localized: "\(title) Mode")
    }

    public var tagline: String {
        switch self {
        case .school: String(localized: "Focused learning")
        case .homework: String(localized: "Limited access")
        case .bedtime: String(localized: "Rest and sleep")
        }
    }

    public var symbol: String {
        switch self {
        case .school: "graduationcap.fill"
        case .homework: "house.fill"
        case .bedtime: "moon.fill"
        }
    }

    /// When two windows overlap, the stricter mode wins.
    public var priority: Int {
        switch self {
        case .bedtime: 3
        case .school: 2
        case .homework: 1
        }
    }
}

public enum ContentCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case socialMedia
    case games
    case entertainment
    case videoStreaming
    case shopping
    case chat
    case adultContent

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .socialMedia: String(localized: "Social Media")
        case .games: String(localized: "Games")
        case .entertainment: String(localized: "Entertainment")
        case .videoStreaming: String(localized: "Video Streaming")
        case .shopping: String(localized: "Shopping")
        case .chat: String(localized: "Chat")
        case .adultContent: String(localized: "Adult Content")
        }
    }

    public var symbol: String {
        switch self {
        case .socialMedia: "person.2.wave.2"
        case .games: "gamecontroller"
        case .entertainment: "popcorn"
        case .videoStreaming: "play.rectangle"
        case .shopping: "bag"
        case .chat: "bubble.left.and.bubble.right"
        case .adultContent: "eye.slash"
        }
    }
}

/// A human-readable stand-in for an app. On device, real app identities are opaque `ApplicationToken`s that only
/// Apple's UI can render; they travel in `AppSelection.familyActivitySelection`. Descriptors power the demo
/// catalogue, previews and tests.
public struct AppDescriptor: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var symbol: String
    public var palette: Int
    public var category: ContentCategory?

    public init(id: String, name: String, symbol: String, palette: Int, category: ContentCategory? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.palette = palette
        self.category = category
    }
}

public struct AppSelection: Hashable, Codable, Sendable {
    public var apps: [AppDescriptor]
    /// Encoded `FamilyControls.FamilyActivitySelection` (opaque tokens) — only meaningful on the device that
    /// produced it.
    public var familyActivitySelection: Data?

    public init(apps: [AppDescriptor] = [], familyActivitySelection: Data? = nil) {
        self.apps = apps
        self.familyActivitySelection = familyActivitySelection
    }

    public var isEmpty: Bool {
        apps.isEmpty && familyActivitySelection == nil
    }
}

public struct ModeSettings: Identifiable, Hashable, Codable, Sendable {
    public var kind: ControlModeKind
    public var isEnabled: Bool
    public var schedule: WeeklySchedule
    public var allowedApps: AppSelection
    public var restrictedCategories: Set<ContentCategory>

    public var id: ControlModeKind {
        kind
    }

    public init(
        kind: ControlModeKind,
        isEnabled: Bool,
        schedule: WeeklySchedule,
        allowedApps: AppSelection = .init(),
        restrictedCategories: Set<ContentCategory> = []
    ) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.schedule = schedule
        self.allowedApps = allowedApps
        self.restrictedCategories = restrictedCategories
    }
}

public enum WebFilterLevel: String, Codable, Sendable, CaseIterable {
    case off
    case limitAdultWebsites
    case allowedWebsitesOnly

    public var title: String {
        switch self {
        case .off: String(localized: "Unrestricted")
        case .limitAdultWebsites: String(localized: "Limit adult websites")
        case .allowedWebsitesOnly: String(localized: "Allowed websites only")
        }
    }
}

public struct AppLimit: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        app.id
    }

    public var app: AppDescriptor
    public var dailyMinutes: Int

    public init(app: AppDescriptor, dailyMinutes: Int) {
        self.app = app
        self.dailyMinutes = dailyMinutes
    }
}

/// Every parental rule for one child. Saved as a single document so the child applies a consistent version
/// (never half of an edit) — the server stamps `revision`, the device ignores stale revisions.
public struct ControlsConfiguration: Hashable, Codable, Sendable {
    public var childID: MemberID
    public var revision: Int
    public var modes: [ModeSettings]
    public var appLimits: [AppLimit]
    public var alwaysAllowed: AppSelection
    public var downtime: WeeklySchedule?
    public var webFilter: WebFilterLevel
    public var dailyScreenTimeMinutes: Int

    public init(
        childID: MemberID,
        revision: Int = 1,
        modes: [ModeSettings],
        appLimits: [AppLimit] = [],
        alwaysAllowed: AppSelection = .init(),
        downtime: WeeklySchedule? = nil,
        webFilter: WebFilterLevel = .limitAdultWebsites,
        dailyScreenTimeMinutes: Int = 180
    ) {
        self.childID = childID
        self.revision = revision
        self.modes = modes
        self.appLimits = appLimits
        self.alwaysAllowed = alwaysAllowed
        self.downtime = downtime
        self.webFilter = webFilter
        self.dailyScreenTimeMinutes = dailyScreenTimeMinutes
    }

    public func mode(_ kind: ControlModeKind) -> ModeSettings? {
        modes.first { $0.kind == kind }
    }

    public mutating func update(_ settings: ModeSettings) {
        if let index = modes.firstIndex(where: { $0.kind == settings.kind }) {
            modes[index] = settings
        } else {
            modes.append(settings)
        }
    }

    public var isProtectionActive: Bool {
        modes.contains(where: \.isEnabled) || webFilter != .off
    }

    public static func defaults(for childID: MemberID) -> ControlsConfiguration {
        ControlsConfiguration(
            childID: childID,
            modes: [
                ModeSettings(
                    kind: .school,
                    isEnabled: true,
                    schedule: WeeklySchedule(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 15, minute: 15), days: Weekday.schoolDays),
                    restrictedCategories: [.socialMedia, .games, .videoStreaming, .shopping]
                ),
                ModeSettings(
                    kind: .homework,
                    isEnabled: false,
                    schedule: WeeklySchedule(start: TimeOfDay(hour: 16), end: TimeOfDay(hour: 18), days: Weekday.schoolDays),
                    restrictedCategories: [.games, .socialMedia]
                ),
                ModeSettings(
                    kind: .bedtime,
                    isEnabled: false,
                    schedule: WeeklySchedule(start: TimeOfDay(hour: 21), end: TimeOfDay(hour: 7), days: Weekday.everyDay),
                    restrictedCategories: Set(ContentCategory.allCases)
                ),
            ]
        )
    }
}

/// The mode currently restricting a child's device.
public struct ActiveMode: Hashable, Codable, Sendable {
    public var kind: ControlModeKind
    public var startedAt: Date
    public var until: Date
    /// Set while an approved extra-time grant temporarily lifts the shields.
    public var pausedUntil: Date?

    public init(kind: ControlModeKind, startedAt: Date, until: Date, pausedUntil: Date? = nil) {
        self.kind = kind
        self.startedAt = startedAt
        self.until = until
        self.pausedUntil = pausedUntil
    }

    public func isPaused(at date: Date) -> Bool {
        pausedUntil.map { date < $0 } ?? false
    }
}

public enum ModeResolver {
    /// The highest-priority enabled mode whose window contains `date`.
    public static func activeMode(
        in configuration: ControlsConfiguration,
        at date: Date,
        grant: ExtraTimeGrant? = nil,
        calendar: Calendar = .current
    ) -> ActiveMode? {
        let candidates = configuration.modes
            .filter(\.isEnabled)
            .compactMap { mode -> ActiveMode? in
                guard let interval = mode.schedule.activeInterval(containing: date, calendar: calendar) else { return nil }
                return ActiveMode(kind: mode.kind, startedAt: interval.start, until: interval.end)
            }
        guard var winner = candidates.max(by: { $0.kind.priority < $1.kind.priority }) else { return nil }
        if let grant, grant.isActive(at: date) {
            winner.pausedUntil = min(grant.endsAt, winner.until)
        }
        return winner
    }

    /// The next instant at which the active mode may change — used to schedule the next UI refresh instead of
    /// polling every minute.
    public static func nextTransition(in configuration: ControlsConfiguration, after date: Date, calendar: Calendar = .current) -> Date? {
        var candidates: [Date] = []
        for mode in configuration.modes where mode.isEnabled {
            if let interval = mode.schedule.activeInterval(containing: date, calendar: calendar) {
                candidates.append(interval.end)
            }
            if let next = mode.schedule.nextStart(after: date, calendar: calendar) {
                candidates.append(next)
            }
        }
        return candidates.min()
    }
}
