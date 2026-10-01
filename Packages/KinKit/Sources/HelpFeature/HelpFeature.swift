public import Domain
public import Observation
public import Routing
public import SwiftUI
import DesignSystem
import KinCore

@MainActor
@Observable
public final class HelpModel {
    public private(set) var report: PermissionHealthReport?
    public private(set) var fixing: PermissionKind?
    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let onReport: @MainActor (PermissionHealthReport) async -> Void

    public init(permissions: any PermissionsProviding, onReport: @escaping @MainActor (PermissionHealthReport) async -> Void = { _ in }) {
        self.permissions = permissions
        self.onReport = onReport
    }

    public var isHealthy: Bool {
        report?.isHealthy ?? true
    }

    public func refresh() async {
        let latest = await permissions.currentReport()
        if latest != report {
            report = latest
            await onReport(latest)
        }
    }

    public func fix(_ kind: PermissionKind) async {
        fixing = kind
        defer { fixing = nil }
        _ = await permissions.request(kind)
        await refresh()
    }
}

public struct HelpView: View {
    @State private var model: HelpModel
    @State private var showsWhy = false
    @Environment(\.scenePhase) private var scenePhase
    let navigate: (ChildRoute) -> Void

    public init(model: HelpModel, navigate: @escaping (ChildRoute) -> Void) {
        _model = State(initialValue: model)
        self.navigate = navigate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.md) {
                if model.isHealthy {
                    HeroCard(
                        tone: .success,
                        symbol: "gearshape.fill",
                        title: String(localized: "Everything is working"),
                        subtitle: String(localized: "Your device is set up and protected. Keep it this way!")
                    )
                } else {
                    HeroCard(
                        tone: .danger,
                        symbol: "exclamationmark",
                        title: String(localized: "Needs attention"),
                        subtitle: String(localized: "Turn these back on so your family can keep you safe.")
                    )
                }
                RowGroup {
                    ForEach(PermissionKind.allCases) { kind in
                        permissionRow(kind)
                        if kind != PermissionKind.allCases.last {
                            RowDivider()
                        }
                    }
                }
                Button { showsWhy = true } label: {
                    HStack(spacing: KinSpace.sm) {
                        ShieldGlyph(symbol: "checkmark", tint: KinColor.info, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Why these permissions?").font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                            Text("They help your family keep you safe, show your location, and make features like check-ins work.")
                                .font(.kinFootnote)
                                .foregroundStyle(KinColor.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(KinColor.textTertiary)
                    }
                    .padding(KinSpace.md)
                    .background(KinColor.infoSoft, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
                }
                .buttonStyle(.kinPressable)
                Button { navigate(.shieldPreview(appName: "Instagram")) } label: {
                    StatusRow(
                        symbol: "hand.raised.fill",
                        tint: KinColor.brand,
                        title: String(localized: "What a limited app looks like"),
                        subtitle: String(localized: "Preview the screen you’ll see during School Mode")
                    )
                }
                .buttonStyle(.kinPressable)
                .kinCard(padding: KinSpace.sm)
            }
            .padding(KinSpace.md)
        }
        .kinScreenBackground()
        .navigationTitle("Help")
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Returning from Settings is the moment a fixed permission becomes visible.
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .sheet(isPresented: $showsWhy) { WhyPermissionsSheet() }
    }

    private func permissionRow(_ kind: PermissionKind) -> some View {
        let state = model.report?[kind] ?? .notDetermined
        return HStack(spacing: KinSpace.sm) {
            IconBadge(kind.symbol, tint: state.isSatisfied ? KinColor.info : KinColor.danger, size: 36)
            Text(kind.title).font(.kinHeadline)
            Spacer()
            if state.isSatisfied {
                Text(kind == .screenTime ? String(localized: "Active") : state.label).font(.kinSubheadline)
                    .foregroundStyle(KinColor.textSecondary)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(KinColor.success).font(.title3)
            } else {
                Button(model.fixing == kind ? String(localized: "…") : String(localized: "Turn on")) { Task { await model.fix(kind) } }
                    .buttonStyle(.borderedProminent)
                    .tint(KinColor.danger)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, KinSpace.sm)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("help.\(kind.rawValue)")
    }
}

struct WhyPermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(PermissionKind.allCases) { kind in
                    Section {
                        Text(kind.rationale)
                    } header: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
                Section {
                    Text(
                        """
                        Your location is only shared with your family, is encrypted \
                        in transit, and location history is deleted after 30 days.
                        """
                    )
                } header: {
                    Label("Your privacy", systemImage: "lock.fill")
                }
            }
            .navigationTitle("Why these permissions?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
