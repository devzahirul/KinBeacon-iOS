public import Domain
public import Foundation
import KinCore
import Supabase

// MARK: - Child device

extension SupabaseKinBackend: CompanionService {
    public func dashboard() async throws -> ChildDashboard {
        let membership = try await membership()
        let me = membership.memberID.rawValue
        let db = client
        async let members: [MemberRow] = call {
            try await db.from("members").select().eq("family_id", value: membership.familyID).execute().value
        }
        async let status: [StatusRow] = call { try await db.from("member_status").select().eq("member_id", value: me).execute().value }
        async let controls: [ControlsRow] = call { try await db.from("controls").select().eq("member_id", value: me).execute().value }
        async let requests: [RequestRow] = call {
            try await db.from("time_requests").select().eq("member_id", value: me).order("created_at", ascending: false).limit(10).execute()
                .value
        }
        async let checkIns: [CheckInRow] = call {
            try await db.from("check_ins").select().eq("member_id", value: me).order("created_at", ascending: false).limit(6).execute()
                .value
        }
        async let alerts: [AlertRow] = call {
            try await db.from("alerts").select().eq("member_id", value: me).order("created_at", ascending: false).limit(6).execute().value
        }
        let now = Date()
        let allMembers = try await members
        guard let mine = allMembers.first(where: { $0.id == me }) else { throw KinError.notFound }
        let guardian = allMembers.first { $0.role == MemberRole.parent.rawValue }
        let requestList = try await requests.map(\.domain)
        let grant = requestList.compactMap { request -> ExtraTimeGrant? in
            guard case let .approved(until) = request.status, until > now else { return nil }
            return ExtraTimeGrant(requestID: request.id, startsAt: now, minutes: Int(until.timeIntervalSince(now) / 60) + 1)
        }.first
        let configuration = try await controls.first?.domain
        let myStatus = try await status.first?.domain(addressFor: nil)
        return try await ChildDashboard(
            member: mine.domain,
            guardianName: guardian?.relationship ?? guardian?.name ?? String(localized: "your parent"),
            activeMode: configuration.flatMap { ModeResolver.activeMode(in: $0, at: now, grant: grant) },
            screenTimeTodayMinutes: 0,
            dailyLimitMinutes: configuration?.dailyScreenTimeMinutes ?? 0,
            recentActivity: ActivityTimeline.events(
                checkIns: checkIns.map(\.domain),
                requests: requestList,
                alerts: alerts.compactMap(\.domain),
                limit: 6
            ),
            isLocationSharing: (myStatus?.permissions[.location] ?? .granted) == .granted,
            isConnected: true,
            battery: myStatus?.battery
        )
    }

    public func dashboardUpdates() -> AsyncStream<ChildDashboard> {
        startMemberLive()
        return dashboardHub.stream()
    }

    public func timeRequestUpdates() -> AsyncStream<TimeRequest> {
        startMemberLive()
        return requestHub.stream()
    }

    public func commandUpdates() -> AsyncStream<RemoteCommand> {
        startMemberLive()
        return commandHub.stream()
    }

    private func startMemberLive() {
        startLive(key: "member") { [weak self] in
            guard let self else { return }
            do {
                let membership = try await membership()
                try await subscribeMember(membership.memberID.rawValue)
            } catch {
                Log.network.error("Device live updates stopped: \(error.localizedDescription, privacy: .public)")
            }
            _ = state.withLock { $0.live.removeValue(forKey: "member") }
        }
    }

    private func subscribeMember(_ memberID: String) async throws {
        let channel = client.channel("kin-member-\(memberID)")
        let schema = SupabaseConfiguration.schema
        let controls = channel.postgresChange(AnyAction.self, schema: schema, table: "controls", filter: .eq("member_id", value: memberID))
        let requests = channel.postgresChange(
            UpdateAction.self,
            schema: schema,
            table: "time_requests",
            filter: .eq("member_id", value: memberID)
        )
        let commands = channel.postgresChange(InsertAction.self, schema: schema, table: "commands", filter: .eq("target", value: memberID))
        try await channel.subscribeWithError()
        defer { Task { [client] in await client.removeChannel(channel) } }

        let reload: @Sendable () async -> Void = { [weak self] in
            guard let self, let dashboard = try? await dashboard() else { return }
            dashboardHub.yield(dashboard)
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await _ in controls {
                    self?.scheduleReload("dashboard", reload)
                }
            }
            group.addTask { [weak self] in
                for await action in requests {
                    guard let self, let row = decode(RequestRow.self, action) else { continue }
                    requestHub.yield(row.domain)
                    scheduleReload("dashboard", reload)
                }
            }
            group.addTask { [weak self] in
                for await action in commands {
                    guard let self, let command = decode(CommandRow.self, action)?.domain else { continue }
                    commandHub.yield(command)
                }
            }
        }
    }

    public func places() async throws -> [Place] {
        try await places(familyID: membership().familyID, maxAge: 0)
    }

    public func controls() async throws -> ControlsConfiguration {
        try await controls(for: membership().memberID)
    }

    public func timeRequests() async throws -> [TimeRequest] {
        let me = try await membership().memberID.rawValue
        let rows: [RequestRow] = try await call {
            try await self.client.from("time_requests").select().eq("member_id", value: me).order("created_at", ascending: false).limit(20)
                .execute().value
        }
        return rows.map(\.domain)
    }

    public func pendingCommands() async throws -> [RemoteCommand] {
        let me = try await membership().memberID.rawValue
        let rows: [CommandRow] = try await call {
            try await self.client.from("commands").select().eq("target", value: me).is("delivered_at", value: nil)
                .gt("expires_at", value: Date().ISO8601Format()).order("issued_at").execute().value
        }
        return rows.compactMap(\.domain)
    }

    public func acknowledge(_ commandID: UUID) async throws {
        try await call {
            _ = try await self.client.from("commands").update(DeliveredPatch(), returning: .minimal).eq("id", value: commandID).execute()
        }
    }

    public func upload(locations: [LocationSample]) async throws {
        guard let latest = locations.max(by: { $0.timestamp < $1.timestamp }) else { return }
        let membership = try await membership()
        let me = membership.memberID.rawValue
        let fid = membership.familyID
        let rows = locations.map {
            SampleRow(
                memberID: me, familyID: fid, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                accuracy: $0.horizontalAccuracy, speed: $0.speed, isStationary: $0.isStationary, recordedAt: $0.timestamp
            )
        }
        try await call { _ = try await self.client.from("location_samples").insert(rows, returning: .minimal).execute() }
        let place = try await GeofenceEvaluator(places: places(familyID: fid)).currentPlace(for: latest.coordinate)
        var patch = StatusPatch(memberID: me, familyID: fid)
        patch.latitude = latest.coordinate.latitude
        patch.longitude = latest.coordinate.longitude
        patch.accuracy = latest.horizontalAccuracy
        patch.speed = latest.speed
        patch.isStationary = latest.isStationary
        patch.locationAt = latest.timestamp
        patch.placeID = place?.id.rawValue
        try await upsert(patch)
    }

    public func submit(_ checkIn: CheckIn) async throws {
        let fid = try await membership().familyID
        try await call {
            _ = try await self.client.from("check_ins").upsert(
                CheckInRow(checkIn, familyID: fid),
                onConflict: "id",
                returning: .minimal,
                ignoreDuplicates: true
            ).execute()
        }
        if checkIn.kind.isUrgent {
            let alert = SafetyAlert(id: checkIn.id, memberID: checkIn.memberID, kind: .needHelp, createdAt: checkIn.createdAt)
            try await insert(alert, familyID: fid, location: checkIn.location)
        }
    }

    public func submit(_ request: TimeRequest) async throws {
        let fid = try await membership().familyID
        try await call {
            _ = try await self.client.from("time_requests").upsert(
                RequestRow(request, familyID: fid),
                onConflict: "id",
                returning: .minimal,
                ignoreDuplicates: true
            ).execute()
        }
    }

    public func triggerSOS(_ event: SOSEvent) async throws {
        let fid = try await membership().familyID
        try await insert(
            SafetyAlert(id: event.id, memberID: event.memberID, kind: .sos, createdAt: event.createdAt),
            familyID: fid,
            location: event.location
        )
        if let location = event.location {
            try await upload(locations: [location])
        }
    }

    /// Diffs against the last server-side report so the parent gets exactly one alert per regression, and resolves
    /// open alerts when the permission comes back.
    public func report(permissions: PermissionHealthReport) async throws {
        let membership = try await membership()
        let me = membership.memberID.rawValue
        let rows: [StatusRow] = try await call {
            try await self.client.from("member_status").select().eq("member_id", value: me).execute().value
        }
        let previous = rows.first?.permissions.map { _ in rows[0].domain(addressFor: nil).permissions } ?? .healthy
        for alert in PermissionHealthEvaluator.alerts(memberID: membership.memberID, from: previous, to: permissions, now: Date()) {
            try await insert(alert, familyID: membership.familyID)
        }
        let recoveredKinds = PermissionHealthEvaluator.recoveries(from: previous, to: permissions).compactMap { kind -> String? in
            switch kind {
            case .location: SafetyAlert.Kind.locationPermissionOff.rawValue
            case .notifications: SafetyAlert.Kind.notificationsOff.rawValue
            case .screenTime: SafetyAlert.Kind.deviceProtectionOff.rawValue
            case .backgroundRefresh: nil
            }
        }
        if !recoveredKinds.isEmpty {
            try await call {
                _ = try await self.client.from("alerts").update(ResolvePatch(), returning: .minimal).eq("member_id", value: me)
                    .in("kind", values: recoveredKinds).is("resolved_at", value: nil).execute()
            }
        }
        var patch = StatusPatch(memberID: me, familyID: membership.familyID)
        patch.permissions = Dictionary(uniqueKeysWithValues: permissions.states.map { ($0.key.rawValue, $0.value.rawValue) })
        try await upsert(patch)
    }

    public func report(battery: BatteryState) async throws {
        let membership = try await membership()
        var patch = StatusPatch(memberID: membership.memberID.rawValue, familyID: membership.familyID)
        patch.batteryLevel = battery.level
        patch.batteryCharging = battery.isCharging
        try await upsert(patch)
    }

    private func upsert(_ patch: StatusPatch) async throws {
        try await call {
            _ = try await self.client.from("member_status").upsert(patch, onConflict: "member_id", returning: .minimal).execute()
        }
    }

    private func insert(_ alert: SafetyAlert, familyID: String, location: LocationSample? = nil) async throws {
        try await call {
            _ = try await self.client.from("alerts").upsert(
                AlertRow(alert, familyID: familyID, location: location),
                onConflict: "id",
                returning: .minimal,
                ignoreDuplicates: true
            )
            .execute()
        }
    }
}
