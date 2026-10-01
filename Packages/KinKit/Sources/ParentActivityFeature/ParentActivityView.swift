public import Routing
public import Session
public import SwiftUI
import DesignSystem
import Domain
import KinCore

public struct ParentActivityView: View {
    let store: FamilyStore
    @State private var model: ActivityModel
    @Environment(\.viewFactories) private var factories
    let navigate: (ParentRoute) -> Void

    public init(store: FamilyStore, model: ActivityModel, navigate: @escaping (ParentRoute) -> Void) {
        self.store = store
        _model = State(initialValue: model)
        self.navigate = navigate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.md) {
                pendingRequests
                Picker("Range", selection: $model.range) {
                    ForEach(ScreenTimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("activity.range")
                PeriodNavigator(title: model.periodTitle, canGoForward: model.canGoForward) { model.step($0) }
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                case .failed(.privateToScreenTime):
                    ScreenTimeReportCard(report: factories.usageReport)
                    if !model.visits.isEmpty {
                        locationActivity
                    }
                case let .failed(error):
                    StateMessageView(symbol: "chart.bar.xaxis", title: String(localized: "No data"), message: error.errorDescription ?? "")
                case let .loaded(summary):
                    ScreenTimeChartCard(summary: summary, comparisonLabel: model.comparisonLabel)
                    TopAppsCard(apps: summary.topApps)
                    if !model.visits.isEmpty {
                        locationActivity
                    }
                }
            }
            .padding(KinSpace.md)
            .animation(.smooth, value: model.phase)
        }
        .kinScreenBackground()
        .navigationTitle("Activity")
        .toolbar {
            if store.children.count > 1 {
                ToolbarItem(placement: .topBarLeading) { ChildSwitcher(store: store) }
            }
        }
        .task(id: model.loadKey(member: store.selectedChildID)) {
            guard let child = store.selectedChildID else { return }
            await model.load(member: child)
        }
    }

    @ViewBuilder
    private var pendingRequests: some View {
        let requests = store.pendingRequests.filter { $0.childID == store.selectedChildID }
        ForEach(requests) { request in
            Button { navigate(.timeRequest(request.id)) } label: {
                HStack(spacing: KinSpace.sm) {
                    IconBadge("clock.fill", tint: KinColor.warning, size: 40, filled: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(store.snapshot?.member(request.childID)?.name ?? "") asked for \(request.option.title)").font(.kinHeadline)
                            .foregroundStyle(KinColor.textPrimary)
                        Text(request.message ?? String(localized: "Tap to review")).font(.kinFootnote)
                            .foregroundStyle(KinColor.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(KinColor.textTertiary)
                }
                .padding(KinSpace.md)
                .background(KinColor.warningSoft, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
            }
            .buttonStyle(.kinPressable)
            .accessibilityIdentifier("activity.pendingRequest")
        }
    }

    private var locationActivity: some View {
        VStack(alignment: .leading, spacing: KinSpace.xs) {
            Text("Location Activity").font(.kinSection)
            ForEach(model.visits) { visit in
                HStack(spacing: KinSpace.sm) {
                    IconBadge(visit.kind.symbol, tint: KinColor.brand, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.placeName).font(.kinSubheadline.weight(.semibold))
                        Text(visit.leftAt
                            .map { "\(KinFormat.time(visit.arrivedAt)) – \(KinFormat.time($0))" } ??
                            String(localized: "\(KinFormat.time(visit.arrivedAt)) – Present"))
                            .font(.kinFootnote)
                            .foregroundStyle(KinColor.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .kinCard()
    }
}

struct ChildSwitcher: View {
    @Bindable var store: FamilyStore

    var body: some View {
        Menu {
            Picker("Child", selection: $store.selectedChildID) {
                ForEach(store.children) { Text($0.name).tag(Optional($0.id)) }
            }
        } label: {
            HStack(spacing: 6) {
                if let child = store.selectedChild {
                    AvatarView(child.avatar, size: 26)
                }
                Text(store.selectedChild?.name ?? "").font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(KinColor.textSecondary)
            }
        }
    }
}

/// Live families: Apple renders usage inside its privacy sandbox (DeviceActivityReport extension).
struct ScreenTimeReportCard: View {
    let report: (@MainActor @Sendable () -> AnyView)?

    var body: some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            Label("Screen Time", systemImage: "hourglass").font(.kinSection)
            if let report {
                report()
            } else {
                Text("Usage is shown on a real iPhone.").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
            }
            Text(
                """
                Provided by Apple’s Screen Time. App usage never leaves Apple’s privacy sandbox — not even \
                KinBeacon’s servers see it. Your child’s iPhone must be in your Family Sharing group.
                """
            )
            .font(.kinFootnote)
            .foregroundStyle(KinColor.textSecondary)
        }
        .kinCard()
    }
}
