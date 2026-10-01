public import Routing
public import Session
public import SwiftUI
import DesignSystem
import Domain
import KinCore

public struct ChildHomeView: View {
    let store: CompanionStore
    let navigate: (ChildRoute) -> Void

    public init(store: CompanionStore, navigate: @escaping (ChildRoute) -> Void) {
        self.store = store
        self.navigate = navigate
    }

    public var body: some View {
        ScrollView {
            if let dashboard = store.dashboard {
                VStack(alignment: .leading, spacing: KinSpace.md) {
                    header(dashboard)
                    HeroCard(
                        tone: .success,
                        symbol: "checkmark",
                        title: String(localized: "You’re protected"),
                        subtitle: String(localized: "Your family is looking out for you")
                    )
                    requestBanner
                    statusList(dashboard)
                    HStack(spacing: KinSpace.sm) {
                        QuickActionTile(
                            symbol: "clock.fill",
                            title: String(localized: "Request More Time"),
                            style: .filled(KinColor.info)
                        ) {
                            navigate(.requestTime(appName: nil))
                        }
                        .accessibilityIdentifier("home.requestTime")
                        QuickActionTile(
                            symbol: "ellipsis.message.fill",
                            title: String(localized: "Check In"),
                            style: .tinted(KinColor.success)
                        ) {
                            navigate(.checkIn)
                        }
                        .accessibilityIdentifier("home.checkIn")
                        QuickActionTile(
                            symbol: "exclamationmark.triangle.fill",
                            title: String(localized: "SOS"),
                            style: .filled(KinColor.danger)
                        ) {
                            navigate(.sos)
                        }
                        .accessibilityIdentifier("home.sos")
                    }
                }
                .padding(KinSpace.md)
            } else if let error = store.error {
                StateMessageView(
                    symbol: "wifi.exclamationmark",
                    title: String(localized: "Can’t reach your family"),
                    message: error.errorDescription ?? ""
                ) {
                    Task { await store.refresh() }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 400)
            }
        }
        .refreshable { await store.refresh() }
        .kinScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func header(_ dashboard: ChildDashboard) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("KinBeacon").font(.kinTitle).foregroundStyle(KinColor.brand)
                Text("Companion").font(.kinSubheadline.weight(.semibold)).foregroundStyle(KinColor.info)
            }
            Spacer()
            AvatarView(dashboard.member.avatar, size: 40)
            Button { navigate(.settings) } label: {
                Image(systemName: "gearshape").font(.title3).foregroundStyle(KinColor.textPrimary).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
    }

    @ViewBuilder
    private var requestBanner: some View {
        if let request = store.latestRequest {
            switch TimeRequestPolicy.resolveExpiry(request, now: .now).status {
            case .pending:
                InlineBanner(.info, message: String(localized: "Waiting for a reply to your \(request.option.title) request…"))
            case let .approved(until) where until > .now:
                InlineBanner(.success, message: String(localized: "Extra time approved until \(KinFormat.time(until))"))
            default:
                EmptyView()
            }
        }
    }

    private func statusList(_ dashboard: ChildDashboard) -> some View {
        RowGroup {
            Button { navigate(.permissionsInfo) } label: {
                StatusRow(
                    symbol: "location.fill",
                    tint: KinColor.info,
                    title: String(localized: "Location Sharing"),
                    subtitle: dashboard.isLocationSharing ? String(localized: "On") : String(localized: "Off — tap to fix")
                )
            }
            RowDivider()
            Button { navigate(.shieldPreview(appName: "Instagram")) } label: {
                if let mode = dashboard.activeMode {
                    StatusRow(
                        symbol: mode.kind.symbol,
                        tint: KinColor.brand,
                        title: mode.kind.modeTitle,
                        subtitle: mode.isPaused(at: .now)
                            ? String(localized: "Paused until \(KinFormat.time(mode.pausedUntil ?? mode.until))")
                            : String(localized: "Active until \(KinFormat.time(mode.until))")
                    )
                } else {
                    StatusRow(
                        symbol: "sparkles",
                        tint: KinColor.success,
                        title: String(localized: "Free time"),
                        subtitle: String(localized: "All your apps are available")
                    )
                }
            }
            .accessibilityIdentifier("home.mode")
            RowDivider()
            StatusRow(
                symbol: dashboard.battery?.isLow == true ? "battery.25percent" : "battery.75percent",
                tint: dashboard.battery?.isLow == true ? KinColor.danger : KinColor.success,
                title: String(localized: "Battery"),
                subtitle: dashboard.battery.map { KinFormat.percent($0.level) } ?? "—",
                showsChevron: false
            ) {
                if let battery = dashboard.battery {
                    BatteryIndicator(battery).labelsHidden()
                }
            }
            RowDivider()
            Button { navigate(.permissionsInfo) } label: {
                StatusRow(
                    symbol: "wifi",
                    tint: KinColor.info,
                    title: dashboard.isConnected ? String(localized: "Connected") : String(localized: "Offline"),
                    subtitle: dashboard
                        .isConnected ? String(localized: "Everything is working") : String(localized: "We’ll sync when you’re back online")
                )
            }
        }
        .buttonStyle(.kinPressable)
    }
}
