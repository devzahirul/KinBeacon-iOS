public import Domain
public import Foundation
import KinCore

/// An in-process, deterministic simulation of the KinBeacon backend.
///
/// It lets a reviewer run every flow on a simulator with no account and no server, and it is what UI tests and
/// App Store screenshots run against. It implements exactly the same protocols as `RESTBackend`, so features cannot
/// tell the difference — which is the point of the protocol boundary.
///
/// The "other side" of the family is simulated: in the parent app, Emma occasionally asks for more time and answers
/// check-in requests; in the child app, Mom approves requests after a short delay.
public actor DemoBackend {
    public struct Configuration: Sendable {
        public enum Perspective: Sendable { case parent, child }

        public var perspective: Perspective
        /// Wall-clock length of one simulated "beat" (reply delays, location jitter).
        public var beat: Duration
        /// Spontaneous events (Emma asking for time). Off in UI tests for determinism.
        public var spontaneousEvents: Bool
        public var calendar: Calendar

        public init(perspective: Perspective, beat: Duration = .seconds(3), spontaneousEvents: Bool = true, calendar: Calendar = .current) {
            self.perspective = perspective
            self.beat = beat
            self.spontaneousEvents = spontaneousEvents
            self.calendar = calendar
        }
    }

    private let configuration: Configuration
    private let now: @Sendable () -> Date

    private var snapshot: FamilySnapshot
    private var controlsByChild: [MemberID: ControlsConfiguration]
    private var requests: [TimeRequest] = []
    private var grants: [MemberID: ExtraTimeGrant] = [:]
    private var activityByMember: [MemberID: [ActivityEvent]]
    private var started = false
    private var tick = 0

    nonisolated let snapshotHub = Broadcaster<FamilySnapshot>(replaysLatest: true)
    nonisolated let eventHub = Broadcaster<FamilyEvent>()
    nonisolated let dashboardHub = Broadcaster<ChildDashboard>(replaysLatest: true)
    nonisolated let requestHub = Broadcaster<TimeRequest>()

    public init(configuration: Configuration, now: @escaping @Sendable () -> Date = { Date() }) {
        self.configuration = configuration
        self.now = now
        let date = now()
        let calendar = configuration.calendar
        let controls = [
            DemoData.emmaID: DemoData.controls(for: DemoData.emmaID, now: date, calendar: calendar),
            DemoData.lucasID: DemoData.controls(for: DemoData.lucasID, now: date, calendar: calendar),
        ]
        controlsByChild = controls
        snapshot = Self.initialSnapshot(now: date, controls: controls, calendar: calendar)
        activityByMember = Self.initialActivity(now: date, controls: controls, calendar: calendar)
        snapshotHub.yield(snapshot)
    }

    // MARK: Simulation loop

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { [weak self] in await self?.run() }
    }

    private func run() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: configuration.beat)
            advance()
        }
    }

    private func advance() {
        tick += 1
        let date = now()
        // Emma fidgets in class: tiny stationary jitter keeps the map alive without crossing geofences.
        if var status = snapshot.statuses[DemoData.emmaID], let location = status.location {
            let jitter = Double(tick % 5 - 2) * 0.00002
            status.location = LocationSample(
                coordinate: Coordinate(latitude: location.coordinate.latitude + jitter, longitude: location.coordinate.longitude - jitter),
                horizontalAccuracy: 25,
                timestamp: date,
                isStationary: true
            )
            status.lastSeen = date
            if tick % 20 == 0, var battery = status.battery {
                battery.level = max(0.05, battery.level - 0.01)
                status.battery = battery
            }
            snapshot.statuses[DemoData.emmaID] = status
        }
        refreshModes(at: date)
        publish()

        if configuration.spontaneousEvents, configuration.perspective == .parent, tick == 2,
           !requests.contains(where: { $0.childID == DemoData.emmaID }) {
            let request = TimeRequest(
                childID: DemoData.emmaID,
                option: .fifteenMinutes,
                message: "Finishing my book report video 🙏",
                appName: "YouTube",
                createdAt: date
            )
            requests.append(request)
            log(.timeRequested(minutes: request.option.minutes), for: DemoData.emmaID, at: date)
            eventHub.yield(.timeRequest(request))
        }
    }

    private func refreshModes(at date: Date) {
        var modes: [MemberID: ActiveMode] = [:]
        for (child, controls) in controlsByChild {
            modes[child] = ModeResolver.activeMode(in: controls, at: date, grant: grants[child], calendar: configuration.calendar)
        }
        snapshot.activeModes = modes
        snapshot.generatedAt = date
    }

    private func publish() {
        snapshotHub.yield(snapshot)
        if configuration.perspective == .child {
            dashboardHub.yield(makeDashboard())
        }
    }

    private func log(_ kind: ActivityEvent.Kind, for member: MemberID, at date: Date) {
        let event = ActivityEvent(memberID: member, kind: kind, timestamp: date)
        activityByMember[member, default: []].insert(event, at: 0)
        eventHub.yield(.activity(event))
    }

    private func afterBeats(_ beats: Int, _ work: @escaping @Sendable (isolated DemoBackend) -> Void) {
        let delay = configuration.beat * beats
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            await self.perform(work)
        }
    }

    private func perform(_ work: @Sendable (isolated DemoBackend) -> Void) {
        work(self)
    }

    private func makeDashboard() -> ChildDashboard {
        let date = now()
        let child = DemoData.emmaID
        let controls = controlsByChild[child] ?? .defaults(for: child)
        let today = ScreenTimeGenerator.hourly(member: child, day: date, now: date, calendar: configuration.calendar)
        return ChildDashboard(
            member: DemoData.emma,
            guardianName: DemoData.sarah.displayName,
            activeMode: ModeResolver.activeMode(in: controls, at: date, grant: grants[child], calendar: configuration.calendar),
            screenTimeTodayMinutes: today.reduce(0) { $0 + $1.minutes },
            dailyLimitMinutes: controls.dailyScreenTimeMinutes,
            recentActivity: Array((activityByMember[child] ?? []).prefix(6)),
            isLocationSharing: snapshot.statuses[child]?.permissions[.location] == .granted,
            isConnected: true,
            battery: snapshot.statuses[child]?.battery
        )
    }
}

// MARK: - Seed data

extension DemoBackend {
    static func initialSnapshot(now: Date, controls: [MemberID: ControlsConfiguration], calendar: Calendar) -> FamilySnapshot {
        var lucasPermissions = PermissionHealthReport.healthy
        lucasPermissions.states[.location] = .denied
        let lucasAlert = SafetyAlert(memberID: DemoData.lucasID, kind: .locationPermissionOff, createdAt: now.addingTimeInterval(-26 * 60))
        var modes: [MemberID: ActiveMode] = [:]
        for (child, configuration) in controls {
            modes[child] = ModeResolver.activeMode(in: configuration, at: now, calendar: calendar)
        }
        return FamilySnapshot(
            familyName: "Our Family",
            members: [DemoData.emma, DemoData.lucas, DemoData.sarah],
            statuses: [
                DemoData.emmaID: MemberStatus(
                    memberID: DemoData.emmaID,
                    location: LocationSample(
                        coordinate: DemoData.school.coordinate,
                        horizontalAccuracy: 20,
                        timestamp: now.addingTimeInterval(-8 * 60),
                        isStationary: true
                    ),
                    placeID: DemoData.school.id,
                    address: DemoData.school.address,
                    battery: BatteryState(level: 0.78),
                    lastSeen: now.addingTimeInterval(-60)
                ),
                DemoData.lucasID: MemberStatus(
                    memberID: DemoData.lucasID,
                    location: LocationSample(
                        coordinate: DemoData.home.coordinate,
                        horizontalAccuracy: 30,
                        timestamp: now.addingTimeInterval(-26 * 60)
                    ),
                    placeID: DemoData.home.id,
                    address: DemoData.home.address,
                    battery: BatteryState(level: 0.54),
                    lastSeen: now.addingTimeInterval(-26 * 60),
                    permissions: lucasPermissions
                ),
                DemoData.parentID: MemberStatus(
                    memberID: DemoData.parentID,
                    location: LocationSample(
                        coordinate: DemoData.downtown,
                        horizontalAccuracy: 15,
                        timestamp: now.addingTimeInterval(-2 * 60)
                    ),
                    address: "Downtown",
                    battery: BatteryState(level: 0.91, isCharging: true),
                    lastSeen: now.addingTimeInterval(-2 * 60)
                ),
            ],
            places: DemoData.places,
            activeModes: modes,
            openAlerts: [lucasAlert],
            generatedAt: now
        )
    }

    static func initialActivity(now: Date, controls: [MemberID: ControlsConfiguration], calendar: Calendar) -> [MemberID: [ActivityEvent]] {
        func at(_ minutesAgo: Int) -> Date {
            now.addingTimeInterval(-Double(minutesAgo) * 60)
        }
        let schoolMode = controls[DemoData.emmaID].flatMap { ModeResolver.activeMode(in: $0, at: now, calendar: calendar) }
        var emma: [ActivityEvent] = [
            ActivityEvent(memberID: DemoData.emmaID, kind: .checkIn(.imOK, message: nil), timestamp: at(18)),
            ActivityEvent(memberID: DemoData.emmaID, kind: .locationShared, timestamp: at(55)),
            ActivityEvent(memberID: DemoData.emmaID, kind: .arrived(placeName: DemoData.school.name), timestamp: at(170)),
        ]
        if let schoolMode {
            emma.append(ActivityEvent(
                memberID: DemoData.emmaID,
                kind: .modeStarted(schoolMode.kind, until: schoolMode.until),
                timestamp: schoolMode.startedAt
            ))
        }
        emma.sort { $0.timestamp > $1.timestamp }
        let lucas = [
            ActivityEvent(memberID: DemoData.lucasID, kind: .permissionChanged(.location, granted: false), timestamp: at(26)),
            ActivityEvent(memberID: DemoData.lucasID, kind: .arrived(placeName: DemoData.home.name), timestamp: at(95)),
        ]
        return [DemoData.emmaID: emma, DemoData.lucasID: lucas]
    }
}

// MARK: - FamilyRepository / FamilyEventFeed

extension DemoBackend: FamilyRepository, FamilyEventFeed {
    public nonisolated func snapshots() -> AsyncStream<FamilySnapshot> {
        Task { await startIfNeeded() }
        return snapshotHub.stream()
    }

    public nonisolated func events() -> AsyncStream<FamilyEvent> {
        Task { await startIfNeeded() }
        return eventHub.stream()
    }

    public func refresh() async throws {
        refreshModes(at: now())
        publish()
    }
}

// MARK: - ParentControlService

extension DemoBackend: ParentControlService {
    public func controls(for child: MemberID) async throws -> ControlsConfiguration {
        guard let controls = controlsByChild[child] else { throw KinError.notFound }
        return controls
    }

    public func save(_ configuration: ControlsConfiguration) async throws -> ControlsConfiguration {
        var saved = configuration
        saved.revision = (controlsByChild[configuration.childID]?.revision ?? 0) + 1
        controlsByChild[configuration.childID] = saved
        refreshModes(at: now())
        publish()
        return saved
    }

    public func pendingRequests() async throws -> [TimeRequest] {
        let date = now()
        return requests.map { TimeRequestPolicy.resolveExpiry($0, now: date) }.filter { $0.status == .pending }
    }

    public func respond(to requestID: UUID, approve: Bool) async throws -> TimeRequest {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { throw KinError.notFound }
        let date = now()
        var request = TimeRequestPolicy.resolveExpiry(requests[index], now: date)
        guard request.status == .pending else { return request }
        if approve {
            let grant = ExtraTimeGrant(requestID: request.id, startsAt: date, minutes: request.option.minutes)
            grants[request.childID] = grant
            request.status = .approved(until: grant.endsAt)
            log(.timeApproved(minutes: request.option.minutes), for: request.childID, at: date)
        } else {
            request.status = .denied
            log(.timeDenied, for: request.childID, at: date)
        }
        requests[index] = request
        requestHub.yield(request)
        refreshModes(at: date)
        publish()
        return request
    }

    public func send(_ action: RemoteCommand.Action, to child: MemberID) async throws {
        switch action {
        case .requestCheckIn:
            afterBeats(1) { backend in
                let checkIn = CheckIn(memberID: child, kind: .imOK, message: "All good, in class 📚", createdAt: backend.now())
                backend.log(.checkIn(.imOK, message: checkIn.message), for: child, at: checkIn.createdAt)
                backend.eventHub.yield(.checkIn(checkIn))
            }
        case let .fixPermissions(kind):
            // The child taps the notification and re-enables the permission a moment later.
            afterBeats(1) { backend in backend.restore(kind, for: child) }
        case .locateNow, .startLiveSession:
            if var status = snapshot.statuses[child] {
                status.lastSeen = now()
                snapshot.statuses[child] = status
                publish()
            }
        case .applyControls, .grantExtraTime, .denyExtraTime, .ping:
            break
        }
    }

    public func resolveAlert(_ alertID: UUID) async throws {
        snapshot.openAlerts.removeAll { $0.id == alertID }
        publish()
    }

    private func restore(_ kind: PermissionKind, for member: MemberID) {
        let date = now()
        guard var status = snapshot.statuses[member] else { return }
        status.permissions.states[kind] = .granted
        if kind == .location {
            status.lastSeen = date
            status.location?.timestamp = date
        }
        snapshot.statuses[member] = status
        snapshot.openAlerts.removeAll { $0.memberID == member && $0.isFixableRemotely }
        log(.permissionChanged(kind, granted: true), for: member, at: date)
        publish()
    }
}

// MARK: - ActivityService

extension DemoBackend: ActivityService {
    public func screenTime(for member: MemberID, range: ScreenTimeRange, anchor: Date) async throws -> ScreenTimeSummary {
        let limit = controlsByChild[member]?.dailyScreenTimeMinutes ?? 180
        return ScreenTimeGenerator.summary(
            member: member,
            range: range,
            anchor: anchor,
            now: now(),
            limit: limit,
            calendar: configuration.calendar
        )
    }

    public func activity(for member: MemberID, limit: Int) async throws -> [ActivityEvent] {
        Array((activityByMember[member] ?? []).prefix(limit))
    }

    public func visits(for member: MemberID, on day: Date) async throws -> [PlaceVisit] {
        let calendar = configuration.calendar
        guard calendar.isDate(day, inSameDayAs: now()) else {
            return [PlaceVisit(placeName: DemoData.home.name, kind: .home, arrivedAt: calendar.startOfDay(for: day), leftAt: day)]
        }
        let date = now()
        let start = calendar.startOfDay(for: date)
        func clock(_ hour: Int, _ minute: Int) -> Date {
            min(
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? date,
                date
            )
        }
        switch member {
        case DemoData.emmaID:
            return [
                PlaceVisit(
                    placeName: DemoData.school.name,
                    kind: .school,
                    arrivedAt: min(clock(8, 12), date.addingTimeInterval(-170 * 60))
                ),
                PlaceVisit(
                    placeName: DemoData.home.name,
                    kind: .home,
                    arrivedAt: start,
                    leftAt: min(clock(7, 51), date.addingTimeInterval(-185 * 60))
                ),
            ]
        default:
            return [PlaceVisit(placeName: DemoData.home.name, kind: .home, arrivedAt: start)]
        }
    }
}

// MARK: - CompanionService (the device is Emma's)

extension DemoBackend: CompanionService {
    public func dashboard() async throws -> ChildDashboard {
        startIfNeeded()
        return makeDashboard()
    }

    public nonisolated func dashboardUpdates() -> AsyncStream<ChildDashboard> {
        Task { await startIfNeeded() }
        return dashboardHub.stream()
    }

    public nonisolated func timeRequestUpdates() -> AsyncStream<TimeRequest> {
        requestHub.stream()
    }

    public func controls() async throws -> ControlsConfiguration {
        try await controls(for: DemoData.emmaID)
    }

    public func timeRequests() async throws -> [TimeRequest] {
        let date = now()
        return requests.filter { $0.childID == DemoData.emmaID }.map { TimeRequestPolicy.resolveExpiry($0, now: date) }
    }

    public func pendingCommands() async throws -> [RemoteCommand] {
        []
    }

    public func upload(locations: [LocationSample]) async throws {
        guard let latest = locations.max(by: { $0.timestamp < $1.timestamp }),
              var status = snapshot.statuses[DemoData.emmaID] else { return }
        status.location = latest
        status.lastSeen = latest.timestamp
        status.placeID = GeofenceEvaluator(places: snapshot.places).currentPlace(for: latest.coordinate)?.id
        snapshot.statuses[DemoData.emmaID] = status
        publish()
    }

    public func submit(_ checkIn: CheckIn) async throws {
        log(.checkIn(checkIn.kind, message: checkIn.message), for: checkIn.memberID, at: checkIn.createdAt)
        eventHub.yield(.checkIn(checkIn))
        publish()
    }

    public func submit(_ request: TimeRequest) async throws {
        guard !requests.contains(where: { $0.id == request.id }) else { return } // idempotent retry
        requests.append(request)
        log(.timeRequested(minutes: request.option.minutes), for: request.childID, at: request.createdAt)
        eventHub.yield(.timeRequest(request))
        publish()
        if configuration.perspective == .child {
            // Simulated parent approves after a couple of beats.
            afterBeats(2) { backend in
                Task { try? await backend.respond(to: request.id, approve: true) }
            }
        }
    }

    public func triggerSOS(_ event: SOSEvent) async throws {
        log(.sos, for: event.memberID, at: event.createdAt)
        snapshot.openAlerts.append(SafetyAlert(memberID: event.memberID, kind: .sos, createdAt: event.createdAt))
        publish()
    }

    public func report(permissions: PermissionHealthReport) async throws {
        guard var status = snapshot.statuses[DemoData.emmaID] else { return }
        let date = now()
        let alerts = PermissionHealthEvaluator.alerts(memberID: DemoData.emmaID, from: status.permissions, to: permissions, now: date)
        status.permissions = permissions
        snapshot.statuses[DemoData.emmaID] = status
        snapshot.openAlerts.append(contentsOf: alerts)
        publish()
    }

    public func report(battery: BatteryState) async throws {
        snapshot.statuses[DemoData.emmaID]?.battery = battery
        publish()
    }
}
