public import Domain
public import Observation
public import Routing
public import Session
import DemoBackend
import Foundation
import KinCore
import LocationKit
import Messaging
import ScreenTimeShared
import SyncEngine
import UserNotifications

/// Everything the child device runs: dashboard, outbox, location pipeline, Screen Time enforcement and remote
/// commands. Alive for as long as this device is in the child role.
@MainActor
@Observable
public final class ChildRuntime {
    public var selectedTab: ChildTab = .home
    public let routers: [ChildTab: Router<ChildRoute>]
    public let store: CompanionStore
    let backend: any ChildBackend
    let sync: SyncEngine
    let location: any LocationTracking
    let screenTime: any ScreenTimeControlling
    let permissions: any PermissionsProviding
    let policyStore: SharedPolicyStore
    let isDemo: Bool
    let familyName: String
    let liveScreenTimeAvailable: Bool
    let liveScreenTimeEnabled: Bool
    let memberID: MemberID

    @ObservationIgnored private let database: DeferredDatabase
    @ObservationIgnored private let pipeline: LocationPipeline
    @ObservationIgnored private let commands: RemoteCommandProcessor
    @ObservationIgnored private var lastReport: PermissionHealthReport?
    @ObservationIgnored private var lastLocation: LocationSample?

    init(
        backend: any ChildBackend,
        memberID: MemberID,
        location: any LocationTracking,
        screenTime: any ScreenTimeControlling,
        permissions: any PermissionsProviding,
        policyStore: SharedPolicyStore,
        isDemo: Bool,
        familyName: String,
        liveScreenTimeAvailable: Bool,
        liveScreenTimeEnabled: Bool
    ) {
        self.backend = backend
        self.location = location
        self.screenTime = screenTime
        self.permissions = permissions
        self.policyStore = policyStore
        self.isDemo = isDemo
        self.familyName = familyName
        self.liveScreenTimeAvailable = liveScreenTimeAvailable
        self.liveScreenTimeEnabled = liveScreenTimeEnabled
        self.memberID = memberID
        routers = Dictionary(uniqueKeysWithValues: ChildTab.allCases.map { ($0, Router<ChildRoute>()) })
        store = CompanionStore(service: backend)

        let database = DeferredDatabase(inMemory: isDemo)
        self.database = database
        let sync = SyncEngine(store: database, service: backend, memberID: memberID)
        self.sync = sync
        pipeline = LocationPipeline(tracker: location, sinks: .init(
            persist: { samples in try? await database.database.append(samples) },
            enqueue: { samples in try? await sync.enqueue(.locations(samples)) },
            flush: { await sync.flush() }
        ))
        commands = RemoteCommandProcessor(device: memberID, authenticator: nil, ledger: database) { _ in }
    }

    public var actions: any CompanionActions {
        sync
    }

    // MARK: School Mode apps chosen on this device

    var schoolApps: AppSelection {
        get { policyStore.loadPolicy()?.deviceAllowedApps ?? AppSelection() }
        set {
            var policy = policyStore.loadPolicy()
                ?? SharedPolicy(configuration: .defaults(for: memberID), childName: "", guardianName: familyName, updatedAt: Date())
            policy.deviceAllowedApps = newValue
            try? policyStore.save(policy)
            Task { try? await screenTime.apply(policy.configuration) }
        }
    }

    func router(_ tab: ChildTab) -> Router<ChildRoute> {
        routers[tab] ?? Router()
    }

    // MARK: Lifetime

    /// Started from the root view's `.task` — after the first frame.
    func run() async {
        store.onRequestUpdate = { [weak self] request in self?.handleRequestUpdate(request) }
        await pipeline.start()
        async let dashboard: Void = store.run()
        async let power: Void = followPower()
        async let connectivity: Void = flushWhenOnline()
        async let setup: Void = initialSync()
        async let commands: Void = followCommands()
        _ = await (dashboard, power, connectivity, setup, commands)
    }

    /// Realtime command delivery while the app runs (the silent push + heartbeat cover the rest).
    private func followCommands() async {
        for await command in backend.commandUpdates() {
            _ = await process(command)
        }
    }

    private func initialSync() async {
        if let places = try? await backend.places() {
            await location.monitor(places: places)
        }
        await applyLatestControls()
        await reportPermissionsIfChanged()
        await drainShieldRequests()
        await sync.flush()
    }

    private func followPower() async {
        #if os(iOS)
            let monitor = PowerMonitor()
            for await context in monitor.updates() {
                await pipeline.update(context: context)
                try? await sync.enqueue(.battery(context.battery))
            }
        #endif
    }

    private func flushWhenOnline() async {
        var wasOnline = true
        for await online in ConnectivityMonitor().updates() {
            if online, !wasOnline {
                await sync.flush()
            }
            wasOnline = online
        }
    }

    private func applyLatestControls() async {
        do {
            let controls = try await backend.controls()
            try await screenTime.apply(controls)
        } catch {
            Log.screenTime.error("Applying controls failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reportPermissionsIfChanged() async {
        let report = await permissions.currentReport()
        guard report != lastReport else { return }
        lastReport = report
        try? await sync.enqueue(.permissions(report))
    }

    /// "Request 15 min" taps on the system shield are queued by the ShieldAction extension; send them now.
    private func drainShieldRequests() async {
        for request in policyStore.drainRequests() {
            _ = try? await sync.requestExtraTime(.fifteenMinutes, message: nil, appName: request.appName)
        }
    }

    private func handleRequestUpdate(_ request: TimeRequest) {
        guard case let .approved(until) = request.status else {
            if request.status == .denied {
                notify(
                    String(localized: "Not this time"),
                    String(localized: "Your extra time request was declined.")
                )
            }
            return
        }
        let grant = ExtraTimeGrant(requestID: request.id, startsAt: Date(), minutes: max(1, Int(until.timeIntervalSinceNow / 60)))
        Task { try? await screenTime.grantExtraTime(grant) }
        notify(String(localized: "Extra time approved 🎉"), String(localized: "Your apps are unlocked until \(KinFormat.time(until))."))
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        Task { try? await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )) }
    }

    // MARK: Remote commands

    func process(_ command: RemoteCommand) async -> RemoteCommandProcessor.Outcome {
        let outcome = await commands.process(command)
        if outcome == .executed {
            await execute(command.action)
        }
        if outcome != .failed {
            try? await backend.acknowledge(command.id)
        }
        return outcome
    }

    private func execute(_ action: RemoteCommand.Action) async {
        switch action {
        case .locateNow, .startLiveSession:
            await pipeline.flushNow()
        case .applyControls:
            await applyLatestControls()
            await store.refresh()
        case let .grantExtraTime(requestID, minutes):
            try? await screenTime.grantExtraTime(ExtraTimeGrant(requestID: requestID, startsAt: Date(), minutes: minutes))
        case .denyExtraTime:
            await store.refresh()
        case .requestCheckIn:
            notify(String(localized: "Check in?"), String(localized: "Your family would like to know you’re OK."))
        case let .fixPermissions(kind):
            notify(String(localized: "\(kind.title) is off"), String(localized: "Tap to turn it back on so your family can keep you safe."))
        case .ping:
            break
        }
    }

    func handle(_ route: NotificationCoordinator.Route) async {
        switch route {
        case .replyOK:
            _ = try? await sync.sendCheckIn(.imOK, message: nil)
        case .openAlert, .openRequest, .openMember, .respond:
            selectedTab = .home
        }
    }

    func open(_ link: DeepLink) {
        guard let (tab, route) = link.childDestination else { return }
        selectedTab = tab
        router(tab).show(route)
    }

    /// Heartbeat: fetch missed commands (silent pushes are best-effort), report health, flush the outbox.
    func backgroundRefresh() async {
        if let pending = try? await backend.pendingCommands() {
            for command in pending {
                _ = await process(command)
            }
        }
        await reportPermissionsIfChanged()
        await drainShieldRequests()
        await sync.flush()
        // Data minimisation: local location history never outlives the 30-day retention window.
        _ = try? await database.database.pruneHistory(olderThan: Self.locationRetentionDays, now: Date())
    }

    static let locationRetentionDays = 30
}
