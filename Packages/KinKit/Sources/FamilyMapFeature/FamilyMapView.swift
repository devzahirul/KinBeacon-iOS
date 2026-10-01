public import Routing
public import SwiftUI
import DesignSystem
import Domain
import KinCore
import MapKit
import Session

public struct FamilyMapView: View {
    @Bindable var model: FamilyMapModel
    let navigate: (ParentRoute) -> Void
    let invite: () -> Void

    public init(model: FamilyMapModel, navigate: @escaping (ParentRoute) -> Void, invite: @escaping () -> Void) {
        self.model = model
        self.navigate = navigate
        self.invite = invite
    }

    public var body: some View {
        ZStack(alignment: .top) {
            map
            header
        }
        .safeAreaInset(edge: .bottom) {
            if let member = model.selectedMember, let snapshot = model.snapshot, snapshot.status(member.id)?.location != nil {
                MemberCard(member: member, snapshot: snapshot, model: model, navigate: navigate)
                    .padding(.horizontal, KinSpace.md)
                    .padding(.bottom, KinSpace.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let snapshot = model.snapshot {
                EmptyFamilyCard(snapshot: snapshot, invite: invite)
                    .padding(.horizontal, KinSpace.md)
                    .padding(.bottom, KinSpace.xs)
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.kinSubheadline.weight(.semibold))
                    .padding(.horizontal, KinSpace.md)
                    .padding(.vertical, KinSpace.sm)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.smooth, value: model.toast)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: model.snapshot != nil, initial: true) { model.frameEveryoneIfNeeded() }
    }

    private var map: some View {
        Map(position: $model.camera) {
            if let snapshot = model.snapshot {
                ForEach(snapshot.places) { place in
                    MapCircle(center: CLLocationCoordinate2D(place.coordinate), radius: place.radius)
                        .foregroundStyle(KinColor.brand.opacity(0.08))
                        .stroke(KinColor.brand.opacity(0.25), lineWidth: 1)
                }
                ForEach(model.mappableMembers) { member in
                    if let coordinate = snapshot.status(member.id)?.location?.coordinate {
                        Annotation(member.name, coordinate: CLLocationCoordinate2D(coordinate), anchor: .bottom) {
                            MemberPin(
                                member: member,
                                label: snapshot.pinLabel(for: member.id),
                                isSelected: model.selectedMember?.id == member.id
                            )
                            .onTapGesture { model.select(member) }
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
        }
        .mapStyle(model.mapStyleIsHybrid ? .hybrid(elevation: .realistic) : .standard(pointsOfInterest: .excludingAll))
        .mapControls { MapCompass() }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: KinSpace.xs) {
                MapCircleButton(symbol: "square.3.layers.3d", label: "Map style") { model.mapStyleIsHybrid.toggle() }
                MapCircleButton(symbol: "location.fill", label: "Show everyone") { model.frameEveryone() }
            }
            .padding(.top, 124)
            .padding(.trailing, KinSpace.md)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        HStack(spacing: KinSpace.sm) {
            HStack(spacing: KinSpace.xs) {
                if let parent = model.snapshot?.members.first(where: { $0.role == .parent }) {
                    AvatarView(parent.avatar, size: 30)
                }
                Text(model.snapshot?.familyName ?? String(localized: "Family"))
                    .font(.kinHeadline)
                    .foregroundStyle(KinColor.textPrimary)
            }
            .padding(.leading, 6)
            .padding(.trailing, KinSpace.sm)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            Spacer()
            Button { navigate(.notifications) } label: {
                Image(systemName: "bell.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KinColor.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(.regularMaterial, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if model.store.badgeCount > 0 {
                            Text("\(model.store.badgeCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(KinColor.danger, in: Circle())
                                .offset(x: 2, y: -2)
                        }
                    }
            }
            .accessibilityLabel(Text("Notifications, \(model.store.badgeCount) new"))
            .accessibilityIdentifier("map.notifications")
            Button(action: invite) {
                Image(systemName: "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(KinColor.brand.gradient, in: Circle())
            }
            .accessibilityLabel("Add family member")
        }
        .padding(.horizontal, KinSpace.md)
        .padding(.top, KinSpace.xs)
    }
}

struct MapCircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(KinColor.brand)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }
}

/// Avatar pin with name and place label. Equatable so the map only re-renders pins whose data changed.
struct MemberPin: View, Equatable {
    let member: FamilyMember
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            AvatarView(member.avatar, size: isSelected ? 58 : 46, ring: isSelected ? KinColor.brand : .white)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(spacing: 0) {
                Text(member.displayName).font(.caption.weight(.bold)).foregroundStyle(KinColor.textPrimary)
                if !label.isEmpty {
                    Text(label).font(.caption2).foregroundStyle(KinColor.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(KinColor.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .animation(.spring(duration: 0.3), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("pin.\(member.name)")
    }
}

struct MemberCard: View {
    let member: FamilyMember
    let snapshot: FamilySnapshot
    let model: FamilyMapModel
    let navigate: (ParentRoute) -> Void

    var body: some View {
        let status = snapshot.status(member.id)
        VStack(spacing: KinSpace.md) {
            Capsule().fill(KinColor.separator).frame(width: 36, height: 5)
            HStack(alignment: .top, spacing: KinSpace.sm) {
                AvatarView(
                    member.avatar,
                    size: 54,
                    ring: KinColor.brand.opacity(0.3),
                    badgeSymbol: snapshot.place(status?.placeID)?.kind.symbol
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName).font(.kinTitle).foregroundStyle(KinColor.textPrimary)
                    Text(snapshot.locationTitle(for: member.id)).font(.kinSubheadline.weight(.medium)).foregroundStyle(KinColor.textPrimary)
                    if let status {
                        Text("\(status.address ?? "") · \(KinFormat.relative(status.lastSeen, now: snapshot.generatedAt))")
                            .font(.kinFootnote)
                            .foregroundStyle(KinColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let battery = status?.battery {
                    BatteryIndicator(battery)
                }
            }
            if !snapshot.alerts(for: member.id).isEmpty, let alert = snapshot.alerts(for: member.id).first {
                Button { navigate(.safetyAlert(alert.id)) } label: {
                    InlineBanner(.error, message: alert.title)
                }
                .buttonStyle(.kinPressable)
                .accessibilityIdentifier("map.alertBanner")
            }
            HStack(spacing: KinSpace.xs) {
                ActionChip(symbol: "location.north.line.fill", title: String(localized: "Directions"), isProminent: true) {
                    model.openDirections()
                }
                if member.role == .child {
                    ActionChip(symbol: "ellipsis.message.fill", title: String(localized: "Check In")) {
                        Task { await model.requestCheckIn() }
                    }
                    .disabled(model.isSendingCheckIn)
                    .accessibilityIdentifier("map.checkIn")
                    ActionChip(
                        symbol: "bell.badge.fill",
                        title: String(localized: "Notify Me"),
                        isOn: model.arrivalAlerts.contains(member.id)
                    ) {
                        model.toggleArrivalAlerts()
                    }
                    ActionChip(symbol: "ellipsis", title: String(localized: "Details")) { navigate(.childDetail(member.id)) }
                        .accessibilityIdentifier("map.details")
                }
            }
        }
        .padding(KinSpace.md)
        .padding(.top, -KinSpace.xs)
        .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .sensoryFeedback(.selection, trigger: member.id)
    }
}

/// First run of a live family: nobody shares a location yet.
struct EmptyFamilyCard: View {
    let snapshot: FamilySnapshot
    let invite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            if let waiting = snapshot.children.first {
                Label("Waiting for \(waiting.name)’s location", systemImage: "location.slash").font(.kinHeadline)
                Text("Once \(waiting.name)’s iPhone is paired and location is set to “Always”, they’ll appear here.")
                    .font(.kinSubheadline)
                    .foregroundStyle(KinColor.textSecondary)
            } else {
                Label("Add your first child", systemImage: "person.crop.circle.badge.plus").font(.kinHeadline)
                Text("Pair your child’s iPhone with a one-time code to see their location and set up School Mode.")
                    .font(.kinSubheadline)
                    .foregroundStyle(KinColor.textSecondary)
            }
            Button("Add a child’s device", action: invite).buttonStyle(.kinPrimary).accessibilityIdentifier("map.addChild")
        }
        .padding(KinSpace.md)
        .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
    }
}
