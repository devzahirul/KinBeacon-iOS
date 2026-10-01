public import Foundation

// Service boundaries. Feature view models depend on these protocols only; adapters (URLSession, SwiftData,
// CoreLocation, FamilyControls, the demo simulator) implement them. Each protocol is deliberately narrow
// (interface segregation) so a test fake implements 3 methods, not 30.

// MARK: - Errors

/// Domain errors surfaced to the UI as state — never swallowed with `try?` on a user-visible path.
public enum KinError: Error, Equatable, Sendable, LocalizedError {
    case offline
    case unauthorized
    case notFound
    case server(status: Int)
    case invalidResponse
    case permissionDenied(PermissionKind)
    case requestRejected(TimeRequestPolicy.Violation)
    case unsupportedOnThisDevice
    /// Screen-time numbers never leave Apple's Screen Time sandbox; they are rendered by the report extension.
    case privateToScreenTime
    case invalidPairingCode
    case tooManyAttempts
    case alreadyPaired
    case authentication(String)

    public var errorDescription: String? {
        switch self {
        case .offline: String(localized: "You’re offline. We’ll send it as soon as you’re connected.")
        case .unauthorized: String(localized: "Your session expired. Please pair this device again.")
        case .notFound: String(localized: "That item no longer exists.")
        case .server: String(localized: "Something went wrong on our side. Please try again.")
        case .invalidResponse: String(localized: "We couldn’t read the server’s response.")
        case let .permissionDenied(kind): String(localized: "\(kind.title) is turned off. You can turn it on in Settings.")
        case let .requestRejected(violation): violation.message
        case .unsupportedOnThisDevice: String(localized: "This feature needs a real iPhone.")
        case .privateToScreenTime: String(localized: "Screen time is shown by Apple’s Screen Time on this device.")
        case .invalidPairingCode: String(localized: "That code didn’t work. Codes expire after 10 minutes — ask for a new one.")
        case .tooManyAttempts: String(localized: "Too many tries. Wait a few minutes and try again.")
        case .alreadyPaired: String(localized: "This device or child is already paired.")
        case let .authentication(message): message
        }
    }

    /// Whether retrying later can succeed (drives the outbox and the "Try again" button).
    public var isTransient: Bool {
        switch self {
        case .offline: true
        case let .server(status): status >= 500 || status == 429
        default: false
        }
    }
}

public extension TimeRequestPolicy.Violation {
    var message: String {
        switch self {
        case .messageTooLong: String(localized: "Your message is too long.")
        case .alreadyPending: String(localized: "You already have a request waiting for a reply.")
        case let .tooManyRequests(retryAfter): String(
                localized: "Too many requests. Try again at \(retryAfter.formatted(date: .omitted, time: .shortened))."
            )
        case .noActiveMode: String(localized: "All your apps are available right now.")
        }
    }
}

// MARK: - Parent side

public enum FamilyEvent: Hashable, Sendable {
    case timeRequest(TimeRequest)
    case checkIn(CheckIn)
    case alert(SafetyAlert)
    case activity(ActivityEvent)
}

public protocol FamilyRepository: Sendable {
    /// Hot stream of the family state; replays the latest value to new subscribers.
    func snapshots() -> AsyncStream<FamilySnapshot>
    func refresh() async throws
}

public protocol FamilyEventFeed: Sendable {
    /// Real-time events (SSE / push / demo simulation) — time requests, check-ins, alerts.
    func events() -> AsyncStream<FamilyEvent>
}

public protocol ParentControlService: Sendable {
    func controls(for child: MemberID) async throws -> ControlsConfiguration
    @discardableResult
    func save(_ configuration: ControlsConfiguration) async throws -> ControlsConfiguration
    func pendingRequests() async throws -> [TimeRequest]
    @discardableResult
    func respond(to requestID: UUID, approve: Bool) async throws -> TimeRequest
    func send(_ action: RemoteCommand.Action, to child: MemberID) async throws
    func resolveAlert(_ alertID: UUID) async throws
}

public struct PlaceVisit: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var placeName: String
    public var kind: PlaceKind
    public var arrivedAt: Date
    public var leftAt: Date?

    public init(id: UUID = UUID(), placeName: String, kind: PlaceKind, arrivedAt: Date, leftAt: Date? = nil) {
        self.id = id
        self.placeName = placeName
        self.kind = kind
        self.arrivedAt = arrivedAt
        self.leftAt = leftAt
    }
}

public protocol ActivityService: Sendable {
    func screenTime(for member: MemberID, range: ScreenTimeRange, anchor: Date) async throws -> ScreenTimeSummary
    func activity(for member: MemberID, limit: Int) async throws -> [ActivityEvent]
    func visits(for member: MemberID, on day: Date) async throws -> [PlaceVisit]
}

// MARK: - Child side

/// The child device's view of the backend (network level — retried by the outbox, never called from views).
public protocol CompanionService: Sendable {
    func dashboard() async throws -> ChildDashboard
    func dashboardUpdates() -> AsyncStream<ChildDashboard>
    func timeRequestUpdates() -> AsyncStream<TimeRequest>
    func controls() async throws -> ControlsConfiguration
    func timeRequests() async throws -> [TimeRequest]
    func pendingCommands() async throws -> [RemoteCommand]
    func upload(locations: [LocationSample]) async throws
    func submit(_ checkIn: CheckIn) async throws
    func submit(_ request: TimeRequest) async throws
    func triggerSOS(_ event: SOSEvent) async throws
    func report(permissions: PermissionHealthReport) async throws
    func report(battery: BatteryState) async throws
    /// The family's safe places, registered as geofences on the child's device. Defaults to none.
    func places() async throws -> [Place]
    /// Commands addressed to this device as they are created (realtime). Defaults to none.
    func commandUpdates() -> AsyncStream<RemoteCommand>
    /// Marks a command as delivered so the heartbeat doesn't fetch it again.
    func acknowledge(_ commandID: UUID) async throws
}

public extension CompanionService {
    func places() async throws -> [Place] {
        []
    }

    func commandUpdates() -> AsyncStream<RemoteCommand> {
        AsyncStream { $0.finish() }
    }

    func acknowledge(_ commandID: UUID) async throws {}
}

/// What child-facing screens call. Implemented by the outbox-backed sync engine: calls return as soon as the action
/// is durably queued, so "Send" works in a lift or a school basement and is delivered when connectivity returns.
public protocol CompanionActions: Sendable {
    func sendCheckIn(_ kind: CheckInKind, message: String?) async throws -> CheckIn
    func requestExtraTime(_ option: ExtraTimeOption, message: String?, appName: String?) async throws -> TimeRequest
    func sendSOS() async throws -> SOSEvent
}

// MARK: - Persistence

public enum OutboxOperation: Hashable, Codable, Sendable {
    case locations([LocationSample])
    case checkIn(CheckIn)
    case timeRequest(TimeRequest)
    case sos(SOSEvent)
    case permissions(PermissionHealthReport)
    case battery(BatteryState)

    /// Lower is sent first: an SOS never waits behind 200 queued location fixes.
    public var priority: Int {
        switch self {
        case .sos: 0
        case .checkIn, .timeRequest: 1
        case .permissions: 2
        case .locations: 3
        case .battery: 4
        }
    }

    public var kindName: String {
        switch self {
        case .locations: "locations"
        case .checkIn: "checkIn"
        case .timeRequest: "timeRequest"
        case .sos: "sos"
        case .permissions: "permissions"
        case .battery: "battery"
        }
    }
}

public struct OutboxEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var operation: OutboxOperation
    public var attempt: Int
    public var createdAt: Date
    public var nextAttemptAt: Date

    public init(id: UUID, operation: OutboxOperation, attempt: Int, createdAt: Date, nextAttemptAt: Date) {
        self.id = id
        self.operation = operation
        self.attempt = attempt
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
    }
}

public protocol OutboxStore: Sendable {
    func enqueue(_ operation: OutboxOperation, at date: Date) async throws -> UUID
    /// Due entries ordered by priority, then age.
    func due(at date: Date, limit: Int) async throws -> [OutboxEntry]
    func markDelivered(_ ids: [UUID]) async throws
    func reschedule(_ id: UUID, attempt: Int, nextAttemptAt: Date) async throws
    func drop(_ id: UUID) async throws
    func count() async throws -> Int
}

public protocol CommandLedger: Sendable {
    func hasSeen(_ id: UUID) async -> Bool
    func record(_ id: UUID, at date: Date) async
}

// MARK: - Platform

public enum LocationAuthorization: String, Codable, Sendable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always

    public var permissionState: PermissionState {
        switch self {
        case .always: .granted
        case .whenInUse: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        }
    }
}

public protocol LocationTracking: Sendable {
    func authorization() async -> LocationAuthorization
    func requestWhenInUse() async -> LocationAuthorization
    func requestAlways() async -> LocationAuthorization
    /// Starts (or joins) tracking. The stream ends when the consuming task is cancelled.
    func samples() -> AsyncStream<LocationSample>
    func setProfile(_ profile: TrackingProfile) async
    func monitor(places: [Place]) async
    func geofenceTransitions() -> AsyncStream<GeofenceTransition>
}

public protocol ScreenTimeControlling: Sendable {
    func authorizationState() async -> PermissionState
    func requestAuthorization(as role: MemberRole) async throws
    /// Persists the policy for the extensions and (re)schedules DeviceActivity monitoring.
    func apply(_ configuration: ControlsConfiguration) async throws
    func grantExtraTime(_ grant: ExtraTimeGrant) async throws
    func removeAllRestrictions() async
}

public protocol PermissionsProviding: Sendable {
    func currentReport() async -> PermissionHealthReport
    func request(_ kind: PermissionKind) async -> PermissionState
}

public protocol NotificationPresenting: Sendable {
    func requestAuthorization() async -> Bool
    func present(_ event: FamilyEvent, memberName: String) async
}
