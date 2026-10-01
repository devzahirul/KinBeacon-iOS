public import Routing
public import SwiftUI
import DesignSystem
import Domain
import KinCore
import Session

public struct ChildDetailView: View {
    @State private var model: ChildProfileModel
    let navigate: (ParentRoute) -> Void

    public init(model: ChildProfileModel, navigate: @escaping (ParentRoute) -> Void) {
        _model = State(initialValue: model)
        self.navigate = navigate
    }

    public var body: some View {
        ScrollView {
            if let member = model.member {
                VStack(spacing: KinSpace.md) {
                    header(member)
                    locationCard
                    healthCard(member)
                    RowGroup {
                        Button { navigate(.locationDetail(model.memberID)) } label: {
                            StatusRow(
                                symbol: "location.fill",
                                tint: KinColor.brand,
                                title: String(localized: "Location"),
                                subtitle: String(localized: "Real-time location · Location history · Safe places · Arrival & leave alerts")
                            )
                        }
                        RowDivider()
                        Button { navigate(.deviceDetail(model.memberID)) } label: {
                            StatusRow(
                                symbol: "iphone",
                                tint: KinColor.info,
                                title: String(localized: "Device"),
                                subtitle: String(localized: "Screen time · App limits · Downtime · Device status · Battery")
                            )
                        }
                        RowDivider()
                        Button { navigate(.safetyDetail(model.memberID)) } label: {
                            StatusRow(
                                symbol: "shield.lefthalf.filled",
                                tint: KinColor.danger,
                                title: String(localized: "Safety"),
                                subtitle: String(localized: "SOS alerts · Unusual activity · Permissions")
                            )
                        }
                    }
                    .buttonStyle(.kinPressable)
                }
                .padding(KinSpace.md)
            } else {
                StateMessageView(
                    symbol: "person.crop.circle.badge.questionmark",
                    title: String(localized: "Not found"),
                    message: String(localized: "This family member is no longer in your family.")
                )
            }
        }
        .kinScreenBackground()
        .navigationTitle(model.member?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Locate now", systemImage: "location.magnifyingglass") { Task { await model.locateNow() } }
                    Button("Ask to check in", systemImage: "ellipsis.message") { Task { await model.requestCheckIn() } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More actions")
            }
        }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: {
            if !$0 {
                model.clearMessage()
            }
        })) {}
        .task { await model.load() }
    }

    private func header(_ member: FamilyMember) -> some View {
        HStack(spacing: KinSpace.md) {
            AvatarView(member.avatar, size: 92, ring: KinColor.brand.opacity(0.35))
            VStack(alignment: .leading, spacing: 6) {
                Text(member.name).font(.kinLargeTitle).foregroundStyle(KinColor.textPrimary)
                Text(member.subtitle).font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
                HStack(spacing: KinSpace.md) {
                    if let battery = model.status?.battery {
                        BatteryIndicator(battery)
                    }
                    Label(
                        model.isOnline ? String(localized: "Online") : String(localized: "Offline"),
                        systemImage: model.isOnline ? "wifi" : "wifi.slash"
                    )
                    .font(.kinFootnote.weight(.semibold))
                    .foregroundStyle(model.isOnline ? KinColor.success : KinColor.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, KinSpace.xs)
    }

    private var locationCard: some View {
        Button { navigate(.locationDetail(model.memberID)) } label: {
            HStack(spacing: KinSpace.sm) {
                IconBadge(model.currentPlace?.kind.symbol ?? "mappin.and.ellipse", tint: KinColor.brand, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.store.snapshot?.locationTitle(for: model.memberID) ?? "").font(.kinHeadline)
                        .foregroundStyle(KinColor.textPrimary)
                    if let status = model.status {
                        Text("\(status.address ?? "") · \(KinFormat.relative(status.lastSeen))").font(.kinFootnote)
                            .foregroundStyle(KinColor.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(KinColor.textTertiary)
            }
            .padding(KinSpace.md)
            .background(KinColor.brandSoft, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
        }
        .buttonStyle(.kinPressable)
    }

    @ViewBuilder
    private func healthCard(_ member: FamilyMember) -> some View {
        if let alert = model.alerts.first {
            Button { navigate(.safetyAlert(alert.id)) } label: {
                healthRow(
                    symbol: "exclamationmark",
                    tint: KinColor.danger,
                    soft: KinColor.dangerSoft,
                    title: alert.title,
                    subtitle: alert.summary(childName: member.name)
                )
            }
            .buttonStyle(.kinPressable)
            .accessibilityIdentifier("child.alert")
        } else {
            healthRow(
                symbol: "checkmark",
                tint: KinColor.success,
                soft: KinColor.successSoft,
                title: String(localized: "All good"),
                subtitle: String(localized: "Location, permissions and device settings are working properly.")
            )
        }
    }

    private func healthRow(symbol: String, tint: Color, soft: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: KinSpace.sm) {
            ShieldGlyph(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.kinHeadline).foregroundStyle(KinColor.textPrimary)
                Text(subtitle).font(.kinFootnote).foregroundStyle(KinColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(KinSpace.md)
        .background(soft, in: RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
