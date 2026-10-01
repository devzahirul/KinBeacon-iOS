public import Observation
public import Routing
public import Session
import ControlsFeature
import Domain
import Foundation
import KinCore
import KinStore
import Messaging

/// Everything the parent UI needs, alive for as long as this device is in the parent role.
@MainActor
@Observable
public final class ParentRuntime {
    public var selectedTab: ParentTab = .map
    public var showsInvite = false
    public let routers: [ParentTab: Router<ParentRoute>]
    public let store: FamilyStore
    let backend: any ParentBackend
    let controlsModels: ControlsModels
    let familyName: String
    let isDemo: Bool

    @ObservationIgnored private let presenter = LocalNotificationPresenter()
    @ObservationIgnored private let cache = SnapshotCache<FamilySnapshot>(name: "family-snapshot")

    init(backend: any ParentBackend, familyName: String, isDemo: Bool) {
        self.backend = backend
        self.familyName = familyName
        self.isDemo = isDemo
        store = FamilyStore(repository: backend, feed: backend, controls: backend)
        controlsModels = ControlsModels { [backend] child in ControlsModel(childID: child, service: backend) }
        routers = Dictionary(uniqueKeysWithValues: ParentTab.allCases.map { ($0, Router<ParentRoute>()) })
    }

    func router(_ tab: ParentTab) -> Router<ParentRoute> {
        routers[tab] ?? Router()
    }

    /// Lifetime work for the parent UI. Started from the root view's `.task`, i.e. after the first frame.
    func run() async {
        if store.snapshot == nil, !isDemo, let cached = await cache.load() {
            // Stale-while-revalidate: show the last known family immediately, the stream replaces it.
            store.seed(cached)
            Log.launch.info("Rendering cached snapshot from \(cached.generatedAt, privacy: .public)")
        }
        store.onEvent = { [weak self] event, snapshot in
            self?.present(event, snapshot: snapshot)
        }
        async let persist: Void = persistSnapshots()
        async let live: Void = store.run()
        _ = await (persist, live)
    }

    private func persistSnapshots() async {
        // Write at most every 30 s — the cache only needs to be "recent", not live.
        var lastWrite = Date.distantPast
        for await snapshot in backend.snapshots() where Date().timeIntervalSince(lastWrite) > 30 {
            lastWrite = Date()
            await cache.save(snapshot)
        }
    }

    private func present(_ event: FamilyEvent, snapshot: FamilySnapshot?) {
        let memberID: MemberID? = switch event {
        case let .timeRequest(request): request.childID
        case let .checkIn(checkIn): checkIn.memberID
        case let .alert(alert): alert.memberID
        case .activity: nil
        }
        guard let memberID, let name = snapshot?.member(memberID)?.name else { return }
        Task { await presenter.present(event, memberName: name) }
    }

    func handle(_ route: NotificationCoordinator.Route) async {
        switch route {
        case let .respond(requestID, approve):
            _ = try? await store.respond(to: requestID, approve: approve)
        case let .openRequest(id):
            open(.request(id))
        case let .openAlert(id):
            open(.alert(id))
        case let .openMember(id):
            open(.member(id))
        case .replyOK:
            break
        }
    }

    func open(_ link: DeepLink) {
        guard let (tab, route) = link.parentDestination else { return }
        selectedTab = tab
        router(tab).show(route)
    }

    func backgroundRefresh() async {
        await store.refresh()
    }
}
