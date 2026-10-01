public import Domain
public import Foundation
import KinCore
import os

/// Production backend over HTTPS. Contract: `docs/API.md`.
///
/// Live data arrives over one SSE connection per role (`/v1/family/stream` for parents, `/v1/me/stream` for
/// children) that is opened lazily when the first screen subscribes and closed when the last one goes away —
/// a backgrounded parent app holds no socket open, which is both a battery and an App Review requirement.
public final class RESTBackend: Sendable {
    private let client: APIClient
    private let reconnectBackoff = ExponentialBackoff(base: .seconds(1), maximum: .seconds(60))

    private let snapshotHub = Broadcaster<FamilySnapshot>(replaysLatest: true)
    private let eventHub = Broadcaster<FamilyEvent>()
    private let dashboardHub = Broadcaster<ChildDashboard>(replaysLatest: true)
    private let requestHub = Broadcaster<TimeRequest>()
    private let liveTasks = OSAllocatedUnfairLock<[String: Task<Void, Never>]>(initialState: [:])

    public init(client: APIClient) {
        self.client = client
    }

    deinit {
        liveTasks.withLock { tasks in tasks.values.forEach { $0.cancel() } }
    }

    // MARK: Live streams

    private func ensureLive(path: String, handle: @escaping @Sendable (ServerSentEvent) -> Void) {
        liveTasks.withLock { tasks in
            guard tasks[path] == nil else { return }
            tasks[path] = Task { [client, reconnectBackoff] in
                var attempt = 0
                while !Task.isCancelled {
                    do {
                        for try await event in try await client.events(path: path) {
                            attempt = 0
                            handle(event)
                        }
                    } catch {
                        Log.network.notice("Live stream \(path, privacy: .public) dropped: \(error.localizedDescription, privacy: .public)")
                    }
                    try? await Task.sleep(for: reconnectBackoff.delay(forAttempt: attempt))
                    attempt += 1
                }
            }
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ event: ServerSentEvent) -> T? {
        try? APIClient.decoder.decode(T.self, from: Data(event.data.utf8))
    }

    private func body(_ value: some Encodable) throws -> Data {
        try APIClient.encoder.encode(value)
    }
}

// MARK: - Parent

extension RESTBackend: FamilyRepository, FamilyEventFeed {
    public func snapshots() -> AsyncStream<FamilySnapshot> {
        startFamilyStream()
        return snapshotHub.stream()
    }

    public func events() -> AsyncStream<FamilyEvent> {
        startFamilyStream()
        return eventHub.stream()
    }

    public func refresh() async throws {
        let snapshot = try await client.send(Endpoint<FamilySnapshot>(path: "v1/family"))
        snapshotHub.yield(snapshot)
    }

    private func startFamilyStream() {
        ensureLive(path: "v1/family/stream") { [snapshotHub, eventHub] event in
            switch event.event {
            case "snapshot": Self.decode(FamilySnapshot.self, event).map(snapshotHub.yield)
            case "timeRequest": Self.decode(TimeRequest.self, event).map { eventHub.yield(.timeRequest($0)) }
            case "checkIn": Self.decode(CheckIn.self, event).map { eventHub.yield(.checkIn($0)) }
            case "alert": Self.decode(SafetyAlert.self, event).map { eventHub.yield(.alert($0)) }
            case "activity": Self.decode(ActivityEvent.self, event).map { eventHub.yield(.activity($0)) }
            default: break
            }
        }
    }
}

extension RESTBackend: ParentControlService {
    public func controls(for child: MemberID) async throws -> ControlsConfiguration {
        try await client.send(Endpoint(path: "v1/children/\(child)/controls"))
    }

    public func save(_ configuration: ControlsConfiguration) async throws -> ControlsConfiguration {
        try await client.send(Endpoint(method: .put, path: "v1/children/\(configuration.childID)/controls", body: body(configuration)))
    }

    public func pendingRequests() async throws -> [TimeRequest] {
        try await client.send(Endpoint(path: "v1/requests", query: [URLQueryItem(name: "status", value: "pending")]))
    }

    public func respond(to requestID: UUID, approve: Bool) async throws -> TimeRequest {
        try await client.send(Endpoint(
            method: .post,
            path: "v1/requests/\(requestID)/response",
            body: body(["approve": approve]),
            idempotencyKey: "\(requestID)-response"
        ))
    }

    public func send(_ action: RemoteCommand.Action, to child: MemberID) async throws {
        _ = try await client.send(Endpoint<NoContent>(
            method: .post,
            path: "v1/children/\(child)/commands",
            body: body(action),
            idempotencyKey: UUID().uuidString
        ))
    }

    public func resolveAlert(_ alertID: UUID) async throws {
        _ = try await client.send(Endpoint<NoContent>(
            method: .post,
            path: "v1/alerts/\(alertID)/resolve",
            idempotencyKey: "\(alertID)-resolve"
        ))
    }
}

extension RESTBackend: ActivityService {
    public func screenTime(for member: MemberID, range: ScreenTimeRange, anchor: Date) async throws -> ScreenTimeSummary {
        try await client.send(Endpoint(path: "v1/members/\(member)/screen-time", query: [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "anchor", value: anchor.formatted(.iso8601)),
        ]))
    }

    public func activity(for member: MemberID, limit: Int) async throws -> [ActivityEvent] {
        try await client.send(Endpoint(path: "v1/members/\(member)/activity", query: [URLQueryItem(name: "limit", value: "\(limit)")]))
    }

    public func visits(for member: MemberID, on day: Date) async throws -> [PlaceVisit] {
        try await client.send(Endpoint(
            path: "v1/members/\(member)/visits",
            query: [URLQueryItem(name: "day", value: day.formatted(.iso8601))]
        ))
    }
}

// MARK: - Child

extension RESTBackend: CompanionService {
    public func dashboard() async throws -> ChildDashboard {
        let dashboard = try await client.send(Endpoint<ChildDashboard>(path: "v1/me/dashboard"))
        dashboardHub.yield(dashboard)
        return dashboard
    }

    public func dashboardUpdates() -> AsyncStream<ChildDashboard> {
        startCompanionStream()
        return dashboardHub.stream()
    }

    public func timeRequestUpdates() -> AsyncStream<TimeRequest> {
        startCompanionStream()
        return requestHub.stream()
    }

    private func startCompanionStream() {
        ensureLive(path: "v1/me/stream") { [dashboardHub, requestHub] event in
            switch event.event {
            case "dashboard": Self.decode(ChildDashboard.self, event).map(dashboardHub.yield)
            case "timeRequest": Self.decode(TimeRequest.self, event).map(requestHub.yield)
            default: break
            }
        }
    }

    public func controls() async throws -> ControlsConfiguration {
        try await client.send(Endpoint(path: "v1/me/controls"))
    }

    public func timeRequests() async throws -> [TimeRequest] {
        try await client.send(Endpoint(path: "v1/me/requests"))
    }

    public func pendingCommands() async throws -> [RemoteCommand] {
        try await client.send(Endpoint(path: "v1/me/commands"))
    }

    public func upload(locations: [LocationSample]) async throws {
        let key = locations.first.map { "loc-\($0.timestamp.timeIntervalSince1970)-\(locations.count)" }
        _ = try await client.send(Endpoint<NoContent>(method: .post, path: "v1/me/locations", body: body(locations), idempotencyKey: key))
    }

    public func submit(_ checkIn: CheckIn) async throws {
        _ = try await client.send(Endpoint<NoContent>(
            method: .post,
            path: "v1/me/check-ins",
            body: body(checkIn),
            idempotencyKey: checkIn.id.uuidString
        ))
    }

    public func submit(_ request: TimeRequest) async throws {
        _ = try await client.send(Endpoint<NoContent>(
            method: .post,
            path: "v1/me/requests",
            body: body(request),
            idempotencyKey: request.id.uuidString
        ))
    }

    public func triggerSOS(_ event: SOSEvent) async throws {
        _ = try await client.send(Endpoint<NoContent>(
            method: .post,
            path: "v1/me/sos",
            body: body(event),
            idempotencyKey: event.id.uuidString
        ))
    }

    public func report(permissions: PermissionHealthReport) async throws {
        _ = try await client.send(Endpoint<NoContent>(method: .put, path: "v1/me/permissions", body: body(permissions)))
    }

    public func report(battery: BatteryState) async throws {
        _ = try await client.send(Endpoint<NoContent>(method: .put, path: "v1/me/battery", body: body(battery)))
    }
}
