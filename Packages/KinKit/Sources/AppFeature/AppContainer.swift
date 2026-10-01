public import Foundation
public import KinCore
public import Messaging
public import Observation
import DemoBackend
import Domain
import KinStore
import LocationKit
import Permissions
import Routing
import ScreenTimeKit
import ScreenTimeShared
import SupabaseBackend

typealias ParentBackend = ActivityService & FamilyAdminService & FamilyEventFeed & FamilyRepository & ParentControlService & PlaceService
typealias ChildBackend = ActivityService & CompanionService

/// Composition root. Owns the session and builds the object graph for the current role — and nothing else.
///
/// Launch-time rule: `init` only parses launch arguments and reads one small UserDefaults value. Every service is
/// built lazily when its role's UI appears, and anything slow (SwiftData, CoreLocation, network) starts inside
/// `.task` *after* the first frame is on screen.
@MainActor
@Observable
public final class AppContainer {
    public enum Phase {
        case onboarding
        case parent(ParentRuntime)
        case child(ChildRuntime)
    }

    public private(set) var phase: Phase
    public let options: LaunchOptions
    var settings: SessionSettings {
        didSet { settings.save(to: defaults) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored public let notifications = NotificationCoordinator()
    @ObservationIgnored private let supabaseConfiguration = SupabaseConfiguration(infoDictionary: Bundle.main.infoDictionary)
    @ObservationIgnored private var cachedLiveBackend: SupabaseKinBackend?
    @ObservationIgnored private var cachedLocationTracker: (any LocationTracking)?

    public init(options: LaunchOptions = LaunchOptions(), defaults: UserDefaults = .standard) {
        let signpost = Perf.begin("launch.container")
        defer { Perf.end("launch.container", signpost) }
        self.options = options
        self.defaults = defaults
        let settings = SessionSettings.load(from: defaults, options: options)
        self.settings = settings
        phase = .onboarding
        if let role = settings.role {
            phase = makePhase(for: role)
        }
    }

    public var isDemo: Bool {
        settings.isDemo
    }

    /// True when this build has backend credentials (Config/Supabase.local.xcconfig). Without them only the demo runs.
    var supportsLiveAccounts: Bool {
        supabaseConfiguration != nil && !options.fastSimulation
    }

    /// The authenticated Supabase client, created on first use (never during launch for demo sessions).
    var liveBackend: SupabaseKinBackend? {
        if let cachedLiveBackend {
            return cachedLiveBackend
        }
        guard let supabaseConfiguration else { return nil }
        let backend = SupabaseKinBackend(configuration: supabaseConfiguration)
        cachedLiveBackend = backend
        return backend
    }

    /// Real CoreLocation / FamilyControls / permission prompts only exist on hardware.
    nonisolated static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    var usesRealPlatformServices: Bool {
        !Self.isSimulator && !options.isRunningTests && !options.fastSimulation
    }

    /// One CoreLocation stack per process, shared by onboarding and every runtime (role switches rebuild runtimes,
    /// but CLLocationManager / CLMonitor must not be duplicated).
    var locationTracker: any LocationTracking {
        if let cachedLocationTracker {
            return cachedLocationTracker
        }
        let tracker: any LocationTracking = usesRealPlatformServices
            ? LiveLocationTracker()
            : SimulatedLocationTracker(start: DemoData.school.coordinate)
        cachedLocationTracker = tracker
        return tracker
    }

    // MARK: Session

    func completeOnboarding(role: MemberRole, familyName: String, isDemo: Bool, membership: FamilyMembership?) {
        settings.role = role
        settings.familyName = familyName
        settings.isDemo = isDemo
        settings.membership = membership
        phase = makePhase(for: role)
    }

    func switchRole() {
        guard settings.isDemo else { return }
        let next: MemberRole = settings.role == .parent ? .child : .parent
        settings.role = next
        phase = makePhase(for: next)
    }

    func signOut() async {
        if !settings.isDemo {
            await liveBackend?.signOut()
        }
        resetSession()
    }

    func deleteAccount() async throws {
        if !settings.isDemo {
            try await liveBackend?.deleteAccount()
        }
        resetSession()
    }

    private func resetSession() {
        settings = SessionSettings()
        phase = .onboarding
    }

    func setLiveScreenTime(_ enabled: Bool) {
        settings.liveScreenTime = enabled
        if case .child = phase {
            phase = makePhase(for: .child)
        }
    }

    /// Onboarding needs real permission prompts before a runtime exists.
    func onboardingPermissions() -> any PermissionsProviding {
        guard usesRealPlatformServices else { return SimulatedPermissionsProvider() }
        #if os(iOS)
            return LivePermissionsProvider(location: locationTracker, screenTime: LiveScreenTimeController { ("", "") })
        #else
            return SimulatedPermissionsProvider()
        #endif
    }

    // MARK: Notifications & push

    /// Wires notification taps / action buttons to whichever runtime is active.
    func installNotificationRouting() {
        notifications.onRoute = { [weak self] route in await self?.handle(route) }
        notifications.onDeviceToken = { [weak self] token in
            guard let self, !settings.isDemo, let backend = liveBackend else { return }
            #if DEBUG
                let sandbox = true
            #else
                let sandbox = false
            #endif
            Task { await backend.registerPushToken(token, sandbox: sandbox) }
        }
    }

    func handle(_ route: NotificationCoordinator.Route) async {
        switch phase {
        case let .parent(runtime): await runtime.handle(route)
        case let .child(runtime): await runtime.handle(route)
        case .onboarding: break
        }
    }

    /// Silent push. In live mode the payload is only a doorbell: the device fetches its commands itself.
    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> RemoteCommandProcessor.Outcome? {
        guard case let .child(runtime) = phase else { return nil }
        if let command = PushPayload.command(from: userInfo) {
            return await runtime.process(command)
        }
        await runtime.backgroundRefresh()
        return .executed
    }

    public func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch phase {
        case let .parent(runtime): runtime.open(link)
        case let .child(runtime): runtime.open(link)
        case .onboarding: break
        }
    }

    /// BGAppRefreshTask entry point (≤ 30 s).
    public func backgroundRefresh() async {
        switch phase {
        case let .child(runtime): await runtime.backgroundRefresh()
        case let .parent(runtime): await runtime.backgroundRefresh()
        case .onboarding: break
        }
    }

    // MARK: Graph

    private func makePhase(for role: MemberRole) -> Phase {
        let signpost = Perf.begin("launch.runtime")
        defer { Perf.end("launch.runtime", signpost) }
        let live = settings.isDemo ? nil : liveBackend
        switch role {
        case .parent:
            let backend: any ParentBackend = live ?? DemoBackend(configuration: demoConfiguration(.parent))
            // Live parents share their own location with the family (uploaded directly; parents' phones are online).
            let location: (any LocationTracking)? = live != nil && usesRealPlatformServices ? locationTracker : nil
            return .parent(ParentRuntime(
                backend: backend,
                account: live,
                location: location,
                familyName: settings.familyName,
                isDemo: live == nil
            ))
        case .child:
            return .child(makeChildRuntime(live: live))
        }
    }

    private func demoConfiguration(_ perspective: DemoBackend.Configuration.Perspective) -> DemoBackend.Configuration {
        DemoBackend.Configuration(
            perspective: perspective,
            beat: options.fastSimulation ? .milliseconds(400) : .seconds(3),
            spontaneousEvents: !options.quietDemo
        )
    }

    private func makeChildRuntime(live: SupabaseKinBackend?) -> ChildRuntime {
        let backend: any ChildBackend = live ?? DemoBackend(configuration: demoConfiguration(.child))
        let policyStore = SharedPolicyStore()
        let location: any LocationTracking
        let screenTime: any ScreenTimeControlling
        let permissions: any PermissionsProviding
        if usesRealPlatformServices {
            location = locationTracker
            // Live families always enforce; the demo only enforces if the user opted in (never by surprise).
            screenTime = live != nil || settings.liveScreenTime
                ? LiveScreenTimeController(policyStore: policyStore) { [familyName = settings.familyName] in ("", familyName) }
                : SimulatedScreenTimeController(policyStore: policyStore)
            #if os(iOS)
                permissions = LivePermissionsProvider(location: location, screenTime: screenTime)
            #else
                permissions = SimulatedPermissionsProvider()
            #endif
        } else {
            location = SimulatedLocationTracker(start: DemoData.school.coordinate)
            screenTime = SimulatedScreenTimeController(policyStore: policyStore)
            permissions = SimulatedPermissionsProvider()
        }
        return ChildRuntime(
            backend: backend,
            memberID: live == nil ? DemoData.emmaID : settings.membership?.memberID ?? DemoData.emmaID,
            location: location,
            screenTime: screenTime,
            permissions: permissions,
            policyStore: policyStore,
            isDemo: live == nil,
            familyName: settings.familyName,
            liveScreenTimeAvailable: usesRealPlatformServices && live == nil,
            liveScreenTimeEnabled: live != nil || settings.liveScreenTime
        )
    }
}
