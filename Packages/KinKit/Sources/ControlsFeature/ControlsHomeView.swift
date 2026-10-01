public import Routing
public import Session
public import SwiftUI
import DesignSystem
import Domain
import KinCore

public struct ControlsHomeView: View {
    let store: FamilyStore
    let models: ControlsModels
    let navigate: (ParentRoute) -> Void

    public init(store: FamilyStore, models: ControlsModels, navigate: @escaping (ParentRoute) -> Void) {
        self.store = store
        self.models = models
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if let child = store.selectedChild {
                ControlsContent(child: child, model: models.model(for: child.id), navigate: navigate)
                    .id(child.id)
            } else {
                ProgressView()
            }
        }
        .kinScreenBackground()
        .navigationTitle("Controls")
        .toolbar {
            if store.children.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    ChildPicker(store: store)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigate(.notifications) } label: {
                    Image(systemName: store.badgeCount > 0 ? "bell.badge.fill" : "bell")
                        .symbolRenderingMode(.multicolor)
                }
                .accessibilityLabel("Notifications")
            }
        }
    }
}

/// Menu to switch which child the tab is showing.
public struct ChildPicker: View {
    @Bindable var store: FamilyStore

    public init(store: FamilyStore) {
        self.store = store
    }

    public var body: some View {
        Menu {
            Picker("Child", selection: $store.selectedChildID) {
                ForEach(store.children) { child in
                    Text(child.name).tag(Optional(child.id))
                }
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
        .accessibilityLabel(Text("Showing \(store.selectedChild?.name ?? ""). Switch child"))
        .accessibilityIdentifier("childPicker")
    }
}

struct ControlsContent: View {
    let child: FamilyMember
    @Bindable var model: ControlsModel
    let navigate: (ParentRoute) -> Void

    var body: some View {
        ScrollView {
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            case let .failed(error):
                StateMessageView(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "Couldn’t load controls"),
                    message: error.errorDescription ?? ""
                ) {
                    Task { await model.load() }
                }
            case .loaded:
                VStack(alignment: .leading, spacing: KinSpace.md) {
                    HeroCard(
                        tone: .success,
                        symbol: "checkmark",
                        title: String(localized: "Protected"),
                        subtitle: String(localized: "Parental controls are active for \(child.name)")
                    )
                    activeModeCard
                    modeTiles
                    RowGroup {
                        row(
                            .appLimits(child.id),
                            symbol: "square.grid.2x2.fill",
                            tint: KinColor.info,
                            title: String(localized: "App Limits"),
                            subtitle: String(localized: "Set time limits for individual apps")
                        )
                        RowDivider()
                        row(
                            .downtime(child.id),
                            symbol: "clock.fill",
                            tint: KinColor.brand,
                            title: String(localized: "Downtime"),
                            subtitle: String(localized: "Schedule when apps are blocked")
                        )
                        RowDivider()
                        row(
                            .alwaysAllowed(child.id),
                            symbol: "checkmark.seal.fill",
                            tint: KinColor.success,
                            title: String(localized: "Always Allowed"),
                            subtitle: String(localized: "Choose apps that are always available")
                        )
                        RowDivider()
                        row(
                            .webFilter(child.id),
                            symbol: "globe",
                            tint: KinColor.danger,
                            title: String(localized: "Web Categories"),
                            subtitle: String(localized: "Block inappropriate content")
                        )
                    }
                }
                .padding(KinSpace.md)
            }
        }
        .refreshable { await model.load() }
        .task { await model.loadIfNeeded() }
    }

    private func row(_ route: ParentRoute, symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        Button { navigate(route) } label: {
            StatusRow(symbol: symbol, tint: tint, title: title, subtitle: subtitle)
        }
        .buttonStyle(.kinPressable)
    }

    @ViewBuilder
    private var activeModeCard: some View {
        if let active = model.activeMode {
            Button { navigate(.modeSchedule(child.id, active.kind)) } label: {
                HStack(spacing: KinSpace.md) {
                    Image(systemName: active.kind == .school ? "building.columns.fill" : active.kind.symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(active.kind.modeTitle).font(.kinTitle)
                            Text(active.isPaused(at: .now) ? "Paused" : "Active")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.25), in: Capsule())
                        }
                        Text("Until \(KinFormat.time(active.until))").font(.kinSubheadline.weight(.semibold))
                        Text(active
                            .isPaused(at: .now) ? String(localized: "Extra time approved") :
                            String(localized: "Only allowed apps are available"))
                            .font(.kinFootnote)
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
                }
                .padding(KinSpace.md)
                .background(
                    LinearGradient(colors: [KinColor.brand, KinColor.brandDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous)
                )
            }
            .buttonStyle(.kinPressable)
            .accessibilityIdentifier("controls.activeMode")
        } else if let next = model.nextModeStart {
            InlineBanner(
                .info,
                message: String(
                    localized: "No mode active right now. \(next.0.modeTitle) starts \(next.1.formatted(.relative(presentation: .named)))."
                )
            )
        }
    }

    private var modeTiles: some View {
        HStack(spacing: KinSpace.sm) {
            ForEach(ControlModeKind.allCases) { kind in
                ModeTile(kind: kind, mode: model.mode(kind), isActive: model.activeMode?.kind == kind) {
                    navigate(.modeSchedule(child.id, kind))
                }
            }
        }
    }
}

struct ModeTile: View {
    let kind: ControlModeKind
    let mode: ModeSettings?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(height: 32)
                Text(kind.title).font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                Text(kind.tagline).font(.kinCaption).foregroundStyle(KinColor.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                Text(isActive ? String(localized: "Active") :
                    (mode?.isEnabled == true ? String(localized: "On") : String(localized: "Set")))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isActive ? .white : KinColor.brand)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(isActive ? AnyShapeStyle(KinColor.brand) : AnyShapeStyle(KinColor.brandSoft), in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KinSpace.md)
            .padding(.horizontal, KinSpace.xs)
            .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous)
                    .strokeBorder(isActive ? KinColor.brand : KinColor.separator, lineWidth: isActive ? 2 : 0.5)
            }
        }
        .buttonStyle(.kinPressable)
        .accessibilityIdentifier("mode.\(kind.rawValue)")
        .accessibilityValue(isActive ? Text("Active") : Text(mode?.isEnabled == true ? "On" : "Off"))
    }

    private var tint: Color {
        switch kind {
        case .school: KinColor.brand
        case .homework: KinColor.warning
        case .bedtime: KinColor.info
        }
    }
}
