public import Foundation
public import KinCore
public import Messaging
public import Observation
import DemoBackend
import Domain
import KinStore
import LocationKit
import Networking
import Permissions
import Routing
import ScreenTimeKit
import ScreenTimeShared

typealias ParentBackend = ActivityService & FamilyEventFeed & FamilyRepository & ParentControlService
typealias ChildBackend = ActivityService & CompanionService

/// Composition root. Owns the session and builds the object graph for the current role — and nothing else.
///
/// Launch-time rule: `init` only parses launch arguments and reads three UserDefaults keys. Every service is built
/// lazily when its role's UI appears, and anything slow (SwiftData, CoreLocation, network) starts inside `.task`
/// *after* the first frame is on screen.
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
        options.apiBaseURL == nil
    }

    /// Real CoreLocation / FamilyControls / permission prompts only exist on hardware.
    nonisolated static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    // MARK: Session

    func completeOnboarding(role: MemberRole, familyName: String) {
        settings.role = role
        settings.familyName = familyName
        phase = makePhase(for: role)
    }

    func switchRole() {
        let next: MemberRole = settings.role == .parent ? .child : .parent
        settings.role = next
        phase = makePhase(for: next)
    }

    func signOut() {
        settings.role = nil
        phase = .onboarding
    }

    func setLiveScreenTime(_ enabled: Bool) {
        settings.liveScreenTime = enabled
        if case .child = phase {
            phase = makePhase(for: .child)
        }
    }

    // MARK: Notifications & push

    /// Wires notification taps / action buttons to whichever runtime is active.
    func installNotificationRouting() {
        notifications.onRoute = { [weak self] route in await self?.handle(route) }
    }

    func handle(_ route: NotificationCoordinator.Route) async {
        switch phase {
        case let .parent(runtime): await runtime.handle(route)
        case let .child(runtime): await runtime.handle(route)
        case .onboarding: break
        }
    }

    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> RemoteCommandProcessor.Outcome? {
        guard case let .child(runtime) = phase, let command = PushPayload.command(from: userInfo) else { return nil }
        return await runtime.process(command)
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
        switch role {
        case .parent:
            return .parent(ParentRuntime(backend: makeParentBackend(), familyName: settings.familyName, isDemo: isDemo))
        case .child:
            return .child(makeChildRuntime())
        }
    }

    private var beat: Duration {
        options.fastSimulation ? .milliseconds(400) : .seconds(3)
    }

    private func makeParentBackend() -> any ParentBackend {
        if let url = options.apiBaseURL {
            return RESTBackend(client: APIClient(baseURL: url))
        }
        return DemoBackend(configuration: .init(perspective: .parent, beat: beat, spontaneousEvents: !options.quietDemo))
    }

    private func makeChildRuntime() -> ChildRuntime {
        let backend: any ChildBackend = if let url = options.apiBaseURL {
            RESTBackend(client: APIClient(baseURL: url))
        } else {
            DemoBackend(configuration: .init(perspective: .child, beat: beat, spontaneousEvents: !options.quietDemo))
        }
        let policyStore = SharedPolicyStore()
        let location: any LocationTracking
        let screenTime: any ScreenTimeControlling
        let permissions: any PermissionsProviding
        if Self.isSimulator || options.isRunningTests || options.fastSimulation {
            location = SimulatedLocationTracker(start: DemoData.school.coordinate)
            screenTime = SimulatedScreenTimeController(policyStore: policyStore)
            permissions = SimulatedPermissionsProvider()
        } else {
            location = LiveLocationTracker()
            screenTime = settings.liveScreenTime
                ? LiveScreenTimeController(policyStore: policyStore) { ("Emma", "Mom") }
                : SimulatedScreenTimeController(policyStore: policyStore)
            #if os(iOS)
                permissions = LivePermissionsProvider(location: location, screenTime: screenTime)
            #else
                permissions = SimulatedPermissionsProvider()
            #endif
        }
        return ChildRuntime(
            backend: backend,
            memberID: DemoData.emmaID,
            location: location,
            screenTime: screenTime,
            permissions: permissions,
            policyStore: policyStore,
            isDemo: isDemo,
            familyName: settings.familyName,
            liveScreenTimeAvailable: !Self.isSimulator,
            liveScreenTimeEnabled: settings.liveScreenTime
        )
    }
}
