public import Domain
public import Observation
import Foundation
import KinCore

/// The child's live dashboard, shared by Home, Activity and Request More Time.
@MainActor
@Observable
public final class CompanionStore {
    public private(set) var dashboard: ChildDashboard?
    public private(set) var requests: [TimeRequest] = []
    public private(set) var error: KinError?

    @ObservationIgnored private let service: any CompanionService
    @ObservationIgnored public var onRequestUpdate: (@MainActor (TimeRequest) -> Void)?

    public init(service: any CompanionService, cached: ChildDashboard? = nil) {
        self.service = service
        dashboard = cached
    }

    public func run() async {
        await refresh()
        async let dashboards: Void = consumeDashboards()
        async let requests: Void = consumeRequestUpdates()
        _ = await (dashboards, requests)
    }

    private func consumeDashboards() async {
        for await dashboard in service.dashboardUpdates() where dashboard != self.dashboard {
            self.dashboard = dashboard
        }
    }

    private func consumeRequestUpdates() async {
        for await request in service.timeRequestUpdates() {
            upsert(request)
            onRequestUpdate?(request)
        }
    }

    public func refresh() async {
        do {
            async let dashboard = service.dashboard()
            async let requests = service.timeRequests()
            self.dashboard = try await dashboard
            self.requests = try await requests.sorted { $0.createdAt > $1.createdAt }
            error = nil
        } catch {
            self.error = error as? KinError ?? .server(status: 0)
        }
    }

    public func upsert(_ request: TimeRequest) {
        requests.removeAll { $0.id == request.id }
        requests.insert(request, at: 0)
    }

    public var latestRequest: TimeRequest? {
        requests.first
    }

    public var activeMode: ActiveMode? {
        dashboard?.activeMode
    }
}
