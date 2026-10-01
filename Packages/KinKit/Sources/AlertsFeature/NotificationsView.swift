public import Routing
public import Session
public import SwiftUI
import DesignSystem
import Domain
import KinCore

/// The bell: everything that needs the parent's attention, most urgent first.
public struct NotificationsView: View {
    let store: FamilyStore
    let navigate: (ParentRoute) -> Void

    public init(store: FamilyStore, navigate: @escaping (ParentRoute) -> Void) {
        self.store = store
        self.navigate = navigate
    }

    public var body: some View {
        List {
            if store.openAlerts.isEmpty, store.pendingRequests.isEmpty, store.recentCheckIns.isEmpty {
                StateMessageView(
                    symbol: "bell.slash",
                    title: String(localized: "You’re all caught up"),
                    message: String(localized: "Alerts, requests and check-ins will show up here.")
                )
                .listRowBackground(Color.clear)
            }
            if !store.openAlerts.isEmpty {
                Section("Needs attention") {
                    ForEach(store.openAlerts.sorted { $0.severity > $1.severity }) { alert in
                        Button { navigate(.safetyAlert(alert.id)) } label: {
                            row(
                                symbol: "exclamationmark.triangle.fill",
                                tint: KinColor.danger,
                                title: alert.title,
                                subtitle: name(alert.memberID),
                                date: alert.createdAt
                            )
                        }
                    }
                }
            }
            if !store.pendingRequests.isEmpty {
                Section("Requests") {
                    ForEach(store.pendingRequests) { request in
                        Button { navigate(.timeRequest(request.id)) } label: {
                            row(
                                symbol: "clock.fill",
                                tint: KinColor.warning,
                                title: String(localized: "\(name(request.childID)) asked for \(request.option.title)"),
                                subtitle: request.message ?? "",
                                date: request.createdAt
                            )
                        }
                    }
                }
            }
            if !store.recentCheckIns.isEmpty {
                Section("Check-ins") {
                    ForEach(store.recentCheckIns) { checkIn in
                        row(
                            symbol: checkIn.kind.symbol,
                            tint: checkIn.kind.isUrgent ? KinColor.danger : KinColor.success,
                            title: "\(name(checkIn.memberID)): \(checkIn.kind.title)",
                            subtitle: checkIn.message ?? "",
                            date: checkIn.createdAt
                        )
                    }
                }
            }
        }
        .navigationTitle("Notifications")
    }

    private func name(_ id: MemberID) -> String {
        store.snapshot?.member(id)?.name ?? ""
    }

    private func row(symbol: String, tint: Color, title: String, subtitle: String, date: Date) -> some View {
        HStack(spacing: KinSpace.sm) {
            IconBadge(symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kinSubheadline.weight(.semibold)).foregroundStyle(KinColor.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.kinFootnote).foregroundStyle(KinColor.textSecondary).lineLimit(2)
                }
            }
            Spacer()
            Text(KinFormat.relative(date)).font(.kinCaption).foregroundStyle(KinColor.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}
