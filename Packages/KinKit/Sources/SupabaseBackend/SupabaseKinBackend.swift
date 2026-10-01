public import Domain
public import Foundation
import KinCore
import os
import Supabase

/// The production backend: Supabase Auth + PostgREST (RLS-protected `kinbeacon` schema) + Realtime.
///
/// One class implements every service protocol so both roles share a single authenticated client. Live data uses
/// Realtime `postgres_changes` filtered by family (parent) or member (child); every change triggers a debounced
/// re-read, so screens always render a consistent snapshot instead of patching state event by event.
public final class SupabaseKinBackend: Sendable {
    struct State {
        var membership: FamilyMembership?
        var places: [Place] = []
        var placesFetchedAt: Date = .distantPast
        var live: [String: Task<Void, Never>] = [:]
        var reloadScheduled: Set<String> = []
    }

    let client: SupabaseClient
    let state = OSAllocatedUnfairLock(initialState: State())
    let snapshotHub = Broadcaster<FamilySnapshot>(replaysLatest: true)
    let eventHub = Broadcaster<FamilyEvent>()
    let dashboardHub = Broadcaster<ChildDashboard>(replaysLatest: true)
    let requestHub = Broadcaster<TimeRequest>()
    let commandHub = Broadcaster<RemoteCommand>()
    /// Emits the channel name once a Realtime channel has joined (diagnostics and deterministic integration tests).
    let liveReadyHub = Broadcaster<String>(replaysLatest: true)
    static let decoder = PostgrestClient.Configuration.jsonDecoder

    /// `storageKey` isolates the Keychain session — integration tests run a parent and a child side by side.
    public init(configuration: SupabaseConfiguration, storageKey: String = "kinbeacon.auth") {
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                db: .init(schema: SupabaseConfiguration.schema),
                auth: .init(storageKey: storageKey, emitLocalSessionAsInitialSession: true),
                global: .init(session: URLSession(configuration: .default))
            )
        )
    }

    deinit {
        state.withLock { $0.live.values.forEach { $0.cancel() } }
    }

    // MARK: Session helpers

    var userID: String? {
        client.auth.currentUser?.id.uuidString.lowercased()
    }

    func membership() async throws -> FamilyMembership {
        if let cached = state.withLock({ $0.membership }) {
            return cached
        }
        guard let userID else { throw KinError.unauthorized }
        let rows: [MemberRow] = try await call {
            try await self.client.from("members").select().eq("user_id", value: userID).limit(1).execute().value
        }
        guard let row = rows.first else { throw KinError.notFound }
        let membership = FamilyMembership(
            memberID: MemberID(rawValue: row.id),
            familyID: row.familyID,
            role: MemberRole(rawValue: row.role) ?? .child
        )
        state.withLock { $0.membership = membership }
        return membership
    }

    func places(familyID: String, maxAge: TimeInterval = 600) async throws -> [Place] {
        let cached = state.withLock { $0.placesFetchedAt.timeIntervalSinceNow > -maxAge ? $0.places : nil }
        if let cached {
            return cached
        }
        let rows: [PlaceRow] = try await call {
            try await self.client.from("places").select().eq("family_id", value: familyID).execute().value
        }
        let places = rows.map(\.domain)
        state.withLock {
            $0.places = places
            $0.placesFetchedAt = Date()
        }
        return places
    }

    /// Maps transport, PostgREST (SQLSTATE) and Auth errors to domain errors the UI can explain.
    func call<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as KinError {
            throw error
        } catch let error as PostgrestError {
            Log.network.error("PostgREST \(error.code ?? "-", privacy: .public): \(error.message, privacy: .public)")
            throw Self.map(postgres: error)
        } catch let error as AuthError {
            throw KinError.authentication(error.message)
        } catch let error as URLError {
            throw [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code)
                ? KinError.offline : KinError.server(status: error.errorCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.network.error("Backend error: \(String(describing: error), privacy: .public)")
            throw KinError.invalidResponse
        }
    }

    static func map(postgres error: PostgrestError) -> KinError {
        switch error.code {
        case "22023": .invalidPairingCode
        case "54000": .tooManyAttempts
        case "23505": .alreadyPaired
        case "42501", "28000", "PGRST301": .unauthorized
        case "PGRST116": .notFound
        default: .server(status: 400)
        }
    }

    // MARK: Live updates

    func startLive(key: String, _ body: @escaping @Sendable () async -> Void) {
        state.withLock { state in
            guard state.live[key] == nil else { return }
            state.live[key] = Task { await body() }
        }
    }

    func stopAllLive() {
        let tasks = state.withLock { state in
            defer { state.live.removeAll() }
            return Array(state.live.values)
        }
        tasks.forEach { $0.cancel() }
    }

    /// Coalesces bursts of change events (a child's device writes status + samples together) into one re-read.
    func scheduleReload(_ key: String, _ reload: @escaping @Sendable () async -> Void) {
        let shouldSchedule = state.withLock { $0.reloadScheduled.insert(key).inserted }
        guard shouldSchedule else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            _ = state.withLock { $0.reloadScheduled.remove(key) }
            await reload()
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ action: some HasRecord) -> T? {
        try? action.decodeRecord(as: T.self, decoder: Self.decoder)
    }
}

// MARK: - Parent: family snapshot & feed

extension SupabaseKinBackend: FamilyRepository, FamilyEventFeed {
    public func snapshots() -> AsyncStream<FamilySnapshot> {
        startFamilyLive()
        return snapshotHub.stream()
    }

    public func events() -> AsyncStream<FamilyEvent> {
        startFamilyLive()
        return eventHub.stream()
    }

    public func refresh() async throws {
        try await snapshotHub.yield(loadSnapshot())
    }

    func loadSnapshot() async throws -> FamilySnapshot {
        let membership = try await membership()
        let fid = membership.familyID
        let db = client
        async let family: [FamilyRow] = call { try await db.from("families").select("id,name").eq("id", value: fid).execute().value }
        async let members: [MemberRow] = call {
            try await db.from("members").select().eq("family_id", value: fid).order("created_at").execute().value
        }
        async let statuses: [StatusRow] = call { try await db.from("member_status").select().eq("family_id", value: fid).execute().value }
        async let alerts: [AlertRow] = call {
            try await db.from("alerts").select().eq("family_id", value: fid).is("resolved_at", value: nil).order(
                "created_at",
                ascending: false
            ).execute().value
        }
        async let controls: [ControlsRow] = call { try await db.from("controls").select().eq("family_id", value: fid).execute().value }
        async let grants: [RequestRow] = call {
            try await db.from("time_requests").select().eq("family_id", value: fid).eq("status", value: "approved")
                .gt("approved_until", value: Date().ISO8601Format()).execute().value
        }
        state.withLock { $0.placesFetchedAt = .distantPast }
        let places = try await places(familyID: fid)
        let now = Date()
        let grantByMember = try await Dictionary(grants.map { ($0.memberID, $0) }, uniquingKeysWith: { first, _ in first })
        var activeModes: [MemberID: ActiveMode] = [:]
        for row in try await controls {
            let grant = grantByMember[row.memberID].map { ExtraTimeGrant(
                requestID: $0.id,
                startsAt: now,
                minutes: Int(($0.approvedUntil ?? now).timeIntervalSince(now) / 60) + 1
            ) }
            activeModes[MemberID(rawValue: row.memberID)] = ModeResolver.activeMode(in: row.domain, at: now, grant: grant)
        }
        let placeByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id.rawValue, $0) })
        let statusByMember = try await Dictionary(statuses.map { row in
            (MemberID(rawValue: row.memberID), row.domain(addressFor: row.placeID.flatMap { placeByID[$0] }))
        }, uniquingKeysWith: { first, _ in first })
        return try await FamilySnapshot(
            familyName: family.first?.name ?? String(localized: "Family"),
            members: members.map(\.domain),
            statuses: statusByMember,
            places: places,
            activeModes: activeModes,
            openAlerts: alerts.compactMap(\.domain),
            generatedAt: now
        )
    }

    private func startFamilyLive() {
        startLive(key: "family") { [weak self] in
            guard let self else { return }
            do {
                let membership = try await membership()
                try await snapshotHub.yield(loadSnapshot())
                try await subscribeFamily(familyID: membership.familyID)
            } catch {
                Log.network.error("Family live updates stopped: \(error.localizedDescription, privacy: .public)")
            }
            _ = state.withLock { $0.live.removeValue(forKey: "family") }
        }
    }

    private func subscribeFamily(familyID: String) async throws {
        let channel = client.channel("kin-family-\(familyID)")
        let filter = RealtimePostgresFilter.eq("family_id", value: familyID)
        let snapshotTables = ["members", "places", "member_status", "controls", "alerts"].map {
            channel.postgresChange(AnyAction.self, schema: SupabaseConfiguration.schema, table: $0, filter: filter)
        }
        let requests = channel.postgresChange(AnyAction.self, schema: SupabaseConfiguration.schema, table: "time_requests", filter: filter)
        let checkIns = channel.postgresChange(InsertAction.self, schema: SupabaseConfiguration.schema, table: "check_ins", filter: filter)
        let newAlerts = channel.postgresChange(InsertAction.self, schema: SupabaseConfiguration.schema, table: "alerts", filter: filter)
        try await channel.subscribeWithError()
        Log.network.info("Family channel subscribed")
        liveReadyHub.yield("family")
        defer { Task { [client] in await client.removeChannel(channel) } }

        let reload: @Sendable () async -> Void = { [weak self] in
            guard let self, let snapshot = try? await loadSnapshot() else { return }
            snapshotHub.yield(snapshot)
        }
        await withTaskGroup(of: Void.self) { group in
            for stream in snapshotTables {
                group.addTask { [weak self] in
                    for await _ in stream {
                        self?.scheduleReload("snapshot", reload)
                    }
                }
            }
            group.addTask { [weak self] in
                for await change in requests {
                    guard let self else { return }
                    let row: RequestRow? = switch change {
                    case let .insert(action): decode(RequestRow.self, action)
                    case let .update(action): decode(RequestRow.self, action)
                    default: nil
                    }
                    if let row {
                        eventHub.yield(.timeRequest(row.domain))
                    }
                    scheduleReload("snapshot", reload)
                }
            }
            group.addTask { [weak self] in
                for await action in checkIns {
                    guard let self, let row = decode(CheckInRow.self, action) else { continue }
                    eventHub.yield(.checkIn(row.domain))
                }
            }
            group.addTask { [weak self] in
                for await action in newAlerts {
                    guard let self, let alert = decode(AlertRow.self, action)?.domain else { continue }
                    eventHub.yield(.alert(alert))
                }
            }
        }
    }
}

// MARK: - Parent: controls, requests, commands

extension SupabaseKinBackend: ParentControlService {
    public func controls(for child: MemberID) async throws -> ControlsConfiguration {
        let rows: [ControlsRow] = try await call {
            try await self.client.from("controls").select().eq("member_id", value: child.rawValue).limit(1).execute().value
        }
        guard let row = rows.first else { throw KinError.notFound }
        return row.domain
    }

    public func save(_ configuration: ControlsConfiguration) async throws -> ControlsConfiguration {
        let rows: [ControlsRow] = try await call {
            try await self.client.from("controls").update(ControlsUpdate(config: configuration))
                .eq("member_id", value: configuration.childID.rawValue).select().execute().value
        }
        guard let row = rows.first else { throw KinError.unauthorized }
        // Nudge the child's device to re-apply its shields now instead of at the next schedule boundary.
        try? await send(.applyControls(revision: row.revision ?? 0), to: configuration.childID)
        return row.domain
    }

    public func pendingRequests() async throws -> [TimeRequest] {
        let fid = try await membership().familyID
        let rows: [RequestRow] = try await call {
            try await self.client.from("time_requests").select().eq("family_id", value: fid).eq("status", value: "pending")
                .order("created_at", ascending: false).execute().value
        }
        return rows.map { TimeRequestPolicy.resolveExpiry($0.domain, now: Date()) }.filter { $0.status == .pending }
    }

    public func respond(to requestID: UUID, approve: Bool) async throws -> TimeRequest {
        let row: RequestRow = try await call {
            try await self.client.rpc("respond_to_request", params: RespondParams(requestID: requestID, approve: approve)).single()
                .execute()
                .value
        }
        return row.domain
    }

    public func send(_ action: RemoteCommand.Action, to child: MemberID) async throws {
        let membership = try await membership()
        let row = CommandRow(familyID: membership.familyID, target: child.rawValue, action: action, issuedBy: membership.memberID.rawValue)
        try await call { _ = try await self.client.from("commands").insert(row).execute() }
    }

    public func resolveAlert(_ alertID: UUID) async throws {
        try await call {
            _ = try await self.client.from("alerts").update(ResolvePatch(), returning: .minimal).eq("id", value: alertID).execute()
        }
    }
}

// MARK: - Activity (both roles)

extension SupabaseKinBackend: ActivityService {
    /// Usage data never leaves Apple's Screen Time sandbox — the app shows the DeviceActivityReport instead.
    public func screenTime(for member: MemberID, range: ScreenTimeRange, anchor: Date) async throws -> ScreenTimeSummary {
        throw KinError.privateToScreenTime
    }

    public func activity(for member: MemberID, limit: Int) async throws -> [ActivityEvent] {
        let db = client
        let id = member.rawValue
        async let checkIns: [CheckInRow] = call {
            try await db.from("check_ins").select().eq("member_id", value: id).order("created_at", ascending: false).limit(limit).execute()
                .value
        }
        async let requests: [RequestRow] = call {
            try await db.from("time_requests").select().eq("member_id", value: id).order("created_at", ascending: false).limit(limit)
                .execute().value
        }
        async let alerts: [AlertRow] = call {
            try await db.from("alerts").select().eq("member_id", value: id).order("created_at", ascending: false).limit(limit).execute()
                .value
        }
        return try await ActivityTimeline.events(
            checkIns: checkIns.map(\.domain),
            requests: requests.map(\.domain),
            alerts: alerts.compactMap(\.domain),
            limit: limit
        )
    }

    public func visits(for member: MemberID, on day: Date) async throws -> [PlaceVisit] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        let fid = try await membership().familyID
        let rows: [SampleRow] = try await call {
            try await self.client.from("location_samples").select().eq("member_id", value: member.rawValue)
                .gte("recorded_at", value: start.ISO8601Format()).lt("recorded_at", value: end.ISO8601Format())
                .order("recorded_at").limit(2000).execute().value
        }
        return try await VisitBuilder.visits(from: rows.map(\.domain), places: places(familyID: fid), now: Date())
    }
}

// MARK: - Places

extension SupabaseKinBackend: PlaceService {
    public func save(_ place: Place) async throws {
        let fid = try await membership().familyID
        try await call { _ = try await self.client.from("places").upsert(
            PlaceRow(place, familyID: fid),
            onConflict: "id",
            returning: .minimal
        ).execute() }
        state.withLock { $0.placesFetchedAt = .distantPast }
        try? await refresh()
    }

    public func deletePlace(_ id: PlaceID) async throws {
        try await call { _ = try await self.client.from("places").delete(returning: .minimal).eq("id", value: id.rawValue).execute() }
        state.withLock { $0.placesFetchedAt = .distantPast }
        try? await refresh()
    }
}

// MARK: - Family admin

extension SupabaseKinBackend: FamilyAdminService {
    /// RLS (`members_delete`) only lets a parent of the same family delete a *child* member; every row that references
    /// the member (status, history, controls, requests, check-ins, alerts, commands) is removed by `on delete cascade`.
    public func removeChild(_ id: MemberID) async throws {
        let rows: [MemberRow] = try await call {
            try await self.client.from("members").delete().eq("id", value: id.rawValue).eq("role", value: "child").select().execute().value
        }
        guard !rows.isEmpty else { throw KinError.unauthorized }
        try? await refresh()
    }
}
