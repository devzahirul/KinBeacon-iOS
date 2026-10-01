public import SwiftUI
import AlertsFeature
import CheckInFeature
import ChildActivityFeature
import ChildHomeFeature
import ChildProfileFeature
import ControlsFeature
import DemoBackend
import DesignSystem
import Domain
import FamilyFeature
import FamilyMapFeature
import HelpFeature
import KinCore
import OnboardingFeature
import ParentActivityFeature
import RequestTimeFeature
import Routing
import Session
import SettingsFeature

/// Picks the UI for the device's role. Kept trivial so the first frame is cheap.
public struct KinRootView: View {
    let container: AppContainer

    public init(container: AppContainer) {
        self.container = container
    }

    public var body: some View {
        Group {
            switch container.phase {
            case .onboarding:
                OnboardingView(model: OnboardingModel(permissions: OnboardingPermissions()) { result in
                    container.completeOnboarding(role: result.role, familyName: result.familyName)
                })
            case let .parent(runtime):
                ParentRootView(runtime: runtime, container: container)
            case let .child(runtime):
                ChildRootView(runtime: runtime, container: container)
            }
        }
        .environment(\.viewFactories, AppPickers.factories(live: !AppContainer.isSimulator && !container.isDemo))
        .tint(KinColor.brand)
        .onAppear { Perf.event("launch.firstFrame") }
        .onOpenURL { container.handle(url: $0) }
    }
}

// MARK: - Parent

struct ParentRootView: View {
    @Bindable var runtime: ParentRuntime
    let container: AppContainer

    var body: some View {
        TabView(selection: $runtime.selectedTab) {
            tab(.map, title: String(localized: "Map"), symbol: "map.fill") {
                FamilyMapView(model: FamilyMapModel(store: runtime.store, controls: runtime.backend), navigate: push(.map)) {
                    runtime.selectedTab = .family
                    runtime.showsInvite = true
                }
            }
            tab(.controls, title: String(localized: "Controls"), symbol: "slider.horizontal.3") {
                ControlsHomeView(store: runtime.store, models: runtime.controlsModels, navigate: push(.controls))
            }
            tab(.activity, title: String(localized: "Activity"), symbol: "chart.bar.fill") {
                ParentActivityView(store: runtime.store, model: ActivityModel(service: runtime.backend), navigate: push(.activity))
            }
            .badge(runtime.store.pendingRequests.count)
            tab(.family, title: String(localized: "Family"), symbol: "person.2.fill") {
                FamilyView(store: runtime.store, showsInvite: $runtime.showsInvite, navigate: push(.family))
            }
        }
        .task { await runtime.run() }
    }

    private func push(_ tab: ParentTab) -> (ParentRoute) -> Void {
        { runtime.router(tab).push($0) }
    }

    private func tab(_ tab: ParentTab, title: String, symbol: String, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { runtime.router(tab).path }, set: { runtime.router(tab).path = $0 })) {
            root().navigationDestination(for: ParentRoute.self) { route in
                ParentDestination(route: route, runtime: runtime, container: container, navigate: push(tab))
            }
        }
        .tabItem { Label(title, systemImage: symbol) }
        .tag(tab)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

/// The only place that maps a route to a screen — features stay unaware of each other.
struct ParentDestination: View {
    let route: ParentRoute
    let runtime: ParentRuntime
    let container: AppContainer
    let navigate: (ParentRoute) -> Void

    var body: some View {
        switch route {
        case let .childDetail(id):
            ChildDetailView(model: profile(id), navigate: navigate)
        case let .locationDetail(id):
            ChildLocationView(model: profile(id))
        case let .deviceDetail(id):
            ChildDeviceView(model: profile(id), navigate: navigate)
        case let .safetyDetail(id):
            ChildSafetyView(model: profile(id), navigate: navigate)
        case let .modeSchedule(id, kind):
            ModeScheduleView(model: runtime.controlsModels.model(for: id), kind: kind)
        case let .appLimits(id):
            AppLimitsView(model: runtime.controlsModels.model(for: id), catalog: DemoData.appCatalog)
        case let .downtime(id):
            DowntimeView(model: runtime.controlsModels.model(for: id))
        case let .alwaysAllowed(id):
            AlwaysAllowedView(model: runtime.controlsModels.model(for: id))
        case let .webFilter(id):
            WebFilterView(model: runtime.controlsModels.model(for: id))
        case let .safetyAlert(id):
            SafetyAlertView(model: SafetyAlertModel(alertID: id, store: runtime.store, controls: runtime.backend))
        case let .timeRequest(id):
            TimeRequestView(model: TimeRequestModel(requestID: id, store: runtime.store))
        case .notifications:
            NotificationsView(store: runtime.store, navigate: navigate)
        case .places:
            FamilyView(store: runtime.store, showsInvite: .constant(false), navigate: navigate)
        case .settings:
            SettingsView(
                info: .init(
                    memberName: "Sarah",
                    role: .parent,
                    familyName: runtime.familyName,
                    isDemo: runtime.isDemo,
                    supportsLiveScreenTime: false,
                    version: AppInfo.version
                ),
                liveScreenTime: .constant(false),
                switchRole: container.switchRole,
                signOut: container.signOut
            )
        }
    }

    private func profile(_ id: MemberID) -> ChildProfileModel {
        ChildProfileModel(memberID: id, store: runtime.store, activity: runtime.backend, controls: runtime.backend)
    }
}

// MARK: - Child

struct ChildRootView: View {
    @Bindable var runtime: ChildRuntime
    let container: AppContainer

    var body: some View {
        TabView(selection: $runtime.selectedTab) {
            tab(.home, title: String(localized: "Home"), symbol: "house.fill") {
                ChildHomeView(store: runtime.store, navigate: push(.home))
            }
            tab(.activity, title: String(localized: "Activity"), symbol: "chart.bar.fill") {
                ChildActivityView(store: runtime.store, model: ActivityModel(service: runtime.backend))
            }
            tab(.help, title: String(localized: "Help"), symbol: "questionmark.circle.fill") {
                HelpView(
                    model: HelpModel(permissions: runtime.permissions) { _ in await runtime.reportPermissionsIfChanged() },
                    navigate: push(.help)
                )
            }
            tab(.settings, title: String(localized: "Settings"), symbol: "gearshape.fill") {
                settings
            }
        }
        .environment(\.viewFactories, AppPickers.factories(live: runtime.liveScreenTimeEnabled && !AppContainer.isSimulator))
        .task { await runtime.run() }
    }

    private var settings: some View {
        SettingsView(
            info: .init(
                memberName: runtime.store.dashboard?.member.name ?? "Emma",
                role: .child,
                familyName: runtime.familyName,
                isDemo: runtime.isDemo,
                supportsLiveScreenTime: runtime.liveScreenTimeAvailable,
                version: AppInfo.version
            ),
            liveScreenTime: Binding(get: { runtime.liveScreenTimeEnabled }, set: { container.setLiveScreenTime($0) }),
            switchRole: container.switchRole,
            signOut: container.signOut
        )
    }

    private func push(_ tab: ChildTab) -> (ChildRoute) -> Void {
        { runtime.router(tab).push($0) }
    }

    private func tab(_ tab: ChildTab, title: String, symbol: String, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { runtime.router(tab).path }, set: { runtime.router(tab).path = $0 })) {
            root().navigationDestination(for: ChildRoute.self) { route in
                ChildDestination(route: route, runtime: runtime, settings: { settings }, navigate: push(tab))
            }
        }
        .tabItem { Label(title, systemImage: symbol) }
        .tag(tab)
    }
}

struct ChildDestination<Settings: View>: View {
    let route: ChildRoute
    let runtime: ChildRuntime
    let settings: () -> Settings
    let navigate: (ChildRoute) -> Void

    var body: some View {
        switch route {
        case let .requestTime(appName):
            RequestTimeView(model: RequestTimeModel(appName: appName, store: runtime.store, actions: runtime.actions))
        case .checkIn:
            CheckInView(model: CheckInModel(store: runtime.store, actions: runtime.actions))
        case .sos:
            SOSView(model: SOSModel(store: runtime.store, actions: runtime.actions))
        case let .shieldPreview(appName):
            ShieldPreviewView(appName: appName, policy: runtime.policyStore.loadPolicy(), navigate: navigate)
        case .permissionsInfo:
            HelpView(model: HelpModel(permissions: runtime.permissions), navigate: navigate)
        case .settings:
            settings()
        }
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }
}
