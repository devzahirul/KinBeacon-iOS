public import Routing
public import SwiftUI
import Charts
import DesignSystem
import Domain
import KinCore
import MapKit

/// Location: live map snippet, today's visits and safe-place alert toggles.
public struct ChildLocationView: View {
    @Bindable var model: ChildProfileModel

    public init(model: ChildProfileModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.md) {
                if let coordinate = model.status?.location?.coordinate, let member = model.member {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                        latitudinalMeters: 900,
                        longitudinalMeters: 900
                    ))) {
                        Annotation(
                            member.name,
                            coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        ) {
                            AvatarView(member.avatar, size: 44, ring: .white)
                        }
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: KinRadius.lg, style: .continuous))
                    .allowsHitTesting(false)
                }
                SectionHeader(String(localized: "Today"))
                VStack(spacing: 0) {
                    if model.visits.isEmpty {
                        Text("No places visited yet today.").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary).padding(
                            .vertical,
                            KinSpace.sm
                        )
                    }
                    ForEach(model.visits) { visit in
                        StatusRow(
                            symbol: visit.kind.symbol,
                            tint: KinColor.brand,
                            title: visit.placeName,
                            subtitle: visitTime(visit),
                            showsChevron: false
                        )
                        if visit.id != model.visits.last?.id {
                            RowDivider()
                        }
                    }
                }
                .kinCard()
                SectionHeader(String(localized: "Safe places"))
                VStack(spacing: 0) {
                    ForEach(model.places) { place in
                        Toggle(isOn: Binding(get: { model.notifiesOnArrival(place) }, set: { model.arrivalAlerts[place.id] = $0 })) {
                            HStack(spacing: KinSpace.sm) {
                                IconBadge(place.kind.symbol, tint: KinColor.success, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).font(.kinHeadline)
                                    Text("Arrival & leave alerts · \(Int(place.radius)) m").font(.kinFootnote)
                                        .foregroundStyle(KinColor.textSecondary)
                                }
                            }
                        }
                        .tint(KinColor.brand)
                        .padding(.vertical, KinSpace.xs)
                        if place.id != model.places.last?.id {
                            RowDivider()
                        }
                    }
                }
                .kinCard()
            }
            .padding(KinSpace.md)
        }
        .kinScreenBackground()
        .navigationTitle("Location")
        .task { await model.load() }
    }

    private func visitTime(_ visit: PlaceVisit) -> String {
        let start = KinFormat.time(visit.arrivedAt)
        guard let left = visit.leftAt else { return String(localized: "\(start) – Present") }
        return "\(start) – \(KinFormat.time(left))"
    }
}

/// Device: screen time today, battery, active mode and quick links to controls.
public struct ChildDeviceView: View {
    @Bindable var model: ChildProfileModel
    let navigate: (ParentRoute) -> Void

    public init(model: ChildProfileModel, navigate: @escaping (ParentRoute) -> Void) {
        self.model = model
        self.navigate = navigate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KinSpace.md) {
                if let summary = model.today {
                    VStack(alignment: .leading, spacing: KinSpace.sm) {
                        Text("Screen time today").font(.kinSubheadline).foregroundStyle(KinColor.textSecondary)
                        HStack(alignment: .firstTextBaseline) {
                            Text(KinFormat.duration(.seconds(summary.totalMinutes * 60))).font(.kinMetric)
                            Spacer()
                            Text("of \(KinFormat.duration(.seconds(summary.dailyLimitMinutes * 60)))").font(.kinSubheadline)
                                .foregroundStyle(KinColor.textSecondary)
                        }
                        ProgressBar(value: summary.limitProgress, tint: summary.limitProgress > 0.9 ? KinColor.danger : KinColor.brand)
                    }
                    .kinCard()
                }
                RowGroup {
                    StatusRow(
                        symbol: "iphone",
                        tint: KinColor.info,
                        title: model.member?.deviceModel ?? String(localized: "Device"),
                        subtitle: model.isOnline ? String(localized: "Online") : String(localized: "Offline"),
                        showsChevron: false
                    ) {
                        if let battery = model.status?.battery {
                            BatteryIndicator(battery)
                        }
                    }
                    RowDivider()
                    StatusRow(
                        symbol: model.activeMode?.kind.symbol ?? "checkmark.circle",
                        tint: KinColor.brand,
                        title: model.activeMode.map { $0.kind.modeTitle } ?? String(localized: "No mode active"),
                        subtitle: model.activeMode
                            .map { String(localized: "Until \(KinFormat.time($0.until))") } ?? String(localized: "All apps available"),
                        showsChevron: false
                    )
                }
                RowGroup {
                    Button { navigate(.appLimits(model.memberID)) } label: {
                        StatusRow(
                            symbol: "square.grid.2x2.fill",
                            tint: KinColor.brand,
                            title: String(localized: "App Limits"),
                            subtitle: String(localized: "Set time limits for individual apps")
                        )
                    }
                    RowDivider()
                    Button { navigate(.downtime(model.memberID)) } label: {
                        StatusRow(
                            symbol: "clock.fill",
                            tint: KinColor.brand,
                            title: String(localized: "Downtime"),
                            subtitle: String(localized: "Schedule when apps are blocked")
                        )
                    }
                }
                .buttonStyle(.kinPressable)
            }
            .padding(KinSpace.md)
        }
        .kinScreenBackground()
        .navigationTitle("Device")
        .task { await model.load() }
    }
}

/// Safety: open alerts, permission health and alert preferences.
public struct ChildSafetyView: View {
    @Bindable var model: ChildProfileModel
    let navigate: (ParentRoute) -> Void

    public init(model: ChildProfileModel, navigate: @escaping (ParentRoute) -> Void) {
        self.model = model
        self.navigate = navigate
    }

    public var body: some View {
        List {
            if !model.alerts.isEmpty {
                Section("Needs attention") {
                    ForEach(model.alerts) { alert in
                        Button { navigate(.safetyAlert(alert.id)) } label: {
                            Label(alert.title, systemImage: "exclamationmark.triangle.fill").foregroundStyle(KinColor.danger)
                        }
                    }
                }
            }
            Section("Device permissions") {
                ForEach(PermissionKind.allCases) { kind in
                    let state = model.status?.permissions[kind] ?? .notDetermined
                    LabeledContent {
                        Image(systemName: state.isSatisfied ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(state.isSatisfied ? KinColor.success : KinColor.danger)
                            .accessibilityLabel(state.label)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }
            Section {
                Toggle("SOS alerts", isOn: $model.sosAlertsEnabled)
                Toggle("Unusual activity", isOn: $model.unusualActivityAlerts)
            } header: {
                Text("Alerts")
            } footer: {
                Text("SOS and “Need help” check-ins are always delivered as Time-Sensitive notifications, even during Focus.")
            }
        }
        .tint(KinColor.brand)
        .navigationTitle("Safety")
    }
}
