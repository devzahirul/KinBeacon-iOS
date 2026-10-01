public import Domain
public import Foundation
public import Observation
import KinCore

/// The parent's live view of the family, shared by the Map, Controls, Activity and Alerts features.
///
/// One store, one subscription to the backend stream — screens read derived values, so a location update
/// re-renders only views that read `snapshot` (Observation tracks property access per view).
@MainActor
@Observable
public final class FamilyStore {
    public private(set) var snapshot: FamilySnapshot?
    public private(set) var pendingRequests: [TimeRequest] = []
    public private(set) var recentCheckIns: [CheckIn] = []
    public private(set) var error: KinError?
    public var selectedChildID: MemberID?

    @ObservationIgnored private let repository: any FamilyRepository
    @ObservationIgnored private let feed: any FamilyEventFeed
    @ObservationIgnored private let controls: any ParentControlService
    @ObservationIgnored public var onEvent: (@MainActor (FamilyEvent, FamilySnapshot?) -> Void)?

    public init(
        repository: any FamilyRepository,
        feed: any FamilyEventFeed,
        controls: any ParentControlService,
        cached: FamilySnapshot? = nil
    ) {
        self.repository = repository
        self.feed = feed
        self.controls = controls
        snapshot = cached
        selectedChildID = cached?.children.first?.id
    }

    /// Runs for the lifetime of the calling task (`.task {}` on the root view → cancelled automatically).
    public func run() async {
        await loadPending()
        async let snapshots: Void = consumeSnapshots()
        async let events: Void = consumeEvents()
        _ = await (snapshots, events)
    }

    private func consumeSnapshots() async {
        for await snapshot in repository.snapshots() {
            apply(snapshot)
        }
    }

    private func consumeEvents() async {
        for await event in feed.events() {
            handle(event)
        }
    }

    /// Stale-while-revalidate: show a cached snapshot until the live stream delivers (never overwrites live data).
    public func seed(_ cached: FamilySnapshot) {
        guard snapshot == nil else { return }
        apply(cached)
    }

    public func refresh() async {
        do {
            try await repository.refresh()
            await loadPending()
            error = nil
        } catch {
            self.error = error as? KinError ?? .server(status: 0)
        }
    }

    private func loadPending() async {
        if let pending = try? await controls.pendingRequests() {
            pendingRequests = pending
        }
    }

    private func apply(_ snapshot: FamilySnapshot) {
        guard snapshot != self.snapshot else { return }
        self.snapshot = snapshot
        if selectedChildID == nil || snapshot.member(selectedChildID ?? "") == nil {
            selectedChildID = snapshot.children.first?.id
        }
    }

    func handle(_ event: FamilyEvent) {
        switch event {
        case let .timeRequest(request):
            pendingRequests.removeAll { $0.id == request.id }
            if request.status == .pending {
                pendingRequests.insert(request, at: 0)
            }
        case let .checkIn(checkIn):
            recentCheckIns.insert(checkIn, at: 0)
            recentCheckIns = Array(recentCheckIns.prefix(20))
        case .alert, .activity:
            break
        }
        onEvent?(event, snapshot)
    }

    @discardableResult
    public func respond(to requestID: UUID, approve: Bool) async throws -> TimeRequest {
        let result = try await controls.respond(to: requestID, approve: approve)
        pendingRequests.removeAll { $0.id == requestID }
        return result
    }

    // MARK: Derived

    public var children: [FamilyMember] {
        snapshot?.children ?? []
    }

    public var selectedChild: FamilyMember? {
        selectedChildID.flatMap { snapshot?.member($0) }
    }

    public var openAlerts: [SafetyAlert] {
        snapshot?.openAlerts ?? []
    }

    public var badgeCount: Int {
        openAlerts.count + pendingRequests.count
    }

    public func request(_ id: UUID) -> TimeRequest? {
        pendingRequests.first { $0.id == id }
    }

    public func alert(_ id: UUID) -> SafetyAlert? {
        openAlerts.first { $0.id == id }
    }
}
