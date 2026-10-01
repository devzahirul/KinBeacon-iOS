public import Domain
public import SwiftUI
import DesignSystem
import KinCore
import Routing

/// "School Schedule" editor — also used for Homework and Bedtime.
public struct ModeScheduleView: View {
    @Bindable var model: ControlsModel
    let kind: ControlModeKind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.viewFactories) private var factories
    @State private var showsPicker = false

    public init(model: ControlsModel, kind: ControlModeKind) {
        self.model = model
        self.kind = kind
    }

    public var body: some View {
        ScrollView {
            if let mode = model.mode(kind) {
                VStack(alignment: .leading, spacing: KinSpace.lg) {
                    enableCard(mode)
                    hours(mode)
                    repeatDays(mode)
                    allowedApps(mode)
                    categories(mode)
                    if let error = model.saveError {
                        InlineBanner(.error, message: error.errorDescription ?? "")
                    }
                }
                .padding(KinSpace.md)
            }
        }
        .kinScreenBackground()
        .navigationTitle(String(localized: "\(kind.title) Schedule"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        if await model.save() {
                            dismiss()
                        }
                    }
                }
                .fontWeight(.semibold)
                .disabled(!model.hasChanges || model.isSaving || model.scheduleWarning(for: kind) != nil)
                .accessibilityIdentifier("schedule.save")
            }
        }
        .sheet(isPresented: $showsPicker) {
            NavigationStack {
                factories.appPicker(Binding(
                    get: { model.mode(kind)?.allowedApps ?? AppSelection() },
                    set: { selection in model.update(kind) { $0.allowedApps = selection } }
                ))
                .navigationTitle("Allowed Apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsPicker = false } } }
            }
        }
        .sensoryFeedback(.success, trigger: model.savedConfirmation)
        .onDisappear {
            if model.hasChanges, !model.isSaving {
                model.discardChanges()
            }
        }
    }

    private func enableCard(_ mode: ModeSettings) -> some View {
        Toggle(isOn: Binding(get: { mode.isEnabled }, set: { value in model.update(kind) { $0.isEnabled = value } })) {
            HStack(spacing: KinSpace.sm) {
                IconBadge(kind.symbol, tint: KinColor.brand, size: 44, filled: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable \(kind.modeTitle)").font(.kinHeadline)
                    Text("Automatically apply during these hours").font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
                }
            }
        }
        .tint(KinColor.brand)
        .kinCard()
        .accessibilityIdentifier("schedule.enabled")
    }

    private func hours(_ mode: ModeSettings) -> some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            Text(kind == .school ? "School Hours" : "Hours").font(.kinHeadline)
            HStack(spacing: KinSpace.sm) {
                timePicker(String(localized: "Start"), value: mode.schedule.start) { time in
                    model.update(kind) { $0.schedule.start = time }
                }
                Text("–").foregroundStyle(KinColor.textSecondary)
                timePicker(String(localized: "End"), value: mode.schedule.end) { time in model.update(kind) { $0.schedule.end = time } }
            }
            if let warning = model.scheduleWarning(for: kind) {
                InlineBanner(.error, message: warning)
            } else if mode.schedule.spansMidnight {
                Text("Ends the next morning").font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
            }
        }
    }

    private func timePicker(_ label: String, value: TimeOfDay, set: @escaping (TimeOfDay) -> Void) -> some View {
        DatePicker(
            label,
            selection: Binding(get: { value.date(on: .now) }, set: { set(TimeOfDay($0)) }),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(KinColor.surface, in: RoundedRectangle(cornerRadius: KinRadius.md, style: .continuous))
        .accessibilityLabel(label)
    }

    private func repeatDays(_ mode: ModeSettings) -> some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            Text("Repeat on").font(.kinHeadline)
            HStack {
                ForEach(Weekday.ordered()) { day in
                    WeekdayToggle(
                        label: day.veryShortName(),
                        accessibilityName: day.shortName(),
                        isOn: mode.schedule.days.contains(day)
                    ) { model.toggle(day, in: kind) }
                        .accessibilityIdentifier("weekday.\(day.rawValue)")
                    if day != Weekday.ordered().last {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func allowedApps(_ mode: ModeSettings) -> some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            SectionHeader(String(localized: "Allowed Apps"), action: (String(localized: "Manage"), { showsPicker = true }))
            Text("Only these apps will be available during \(kind.title.lowercased()) hours.").font(.kinFootnote)
                .foregroundStyle(KinColor.textSecondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: KinSpace.sm, alignment: .top), count: 5),
                spacing: KinSpace.md
            ) {
                ForEach(mode.allowedApps.apps) { app in
                    VStack(spacing: 4) {
                        AppIconView(app, size: 50)
                        Text(app.name).font(.caption2).foregroundStyle(KinColor.textSecondary).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .contextMenu {
                        Button("Remove", systemImage: "minus.circle", role: .destructive) { model.removeAllowedApp(app, in: kind) }
                    }
                }
                Button { showsPicker = true } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(KinColor.separator, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .frame(width: 50, height: 50)
                            .overlay(Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(KinColor.brand))
                        Text("Add").font(.caption2).foregroundStyle(KinColor.textSecondary)
                    }
                }
                .accessibilityLabel("Add allowed app")
            }
            if mode.allowedApps.familyActivitySelection != nil {
                Label("Apps chosen on this iPhone", systemImage: "checkmark.shield").font(.kinFootnote).foregroundStyle(KinColor.success)
            }
        }
        .kinCard()
    }

    private func categories(_ mode: ModeSettings) -> some View {
        VStack(alignment: .leading, spacing: KinSpace.sm) {
            Text("Restricted Categories").font(.kinHeadline)
            Text("Block these types of content and apps.").font(.kinFootnote).foregroundStyle(KinColor.textSecondary)
            FlowLayout(spacing: KinSpace.xs) {
                ForEach(ContentCategory.allCases) { category in
                    CategoryChip(title: category.title, symbol: category.symbol, isOn: mode.restrictedCategories.contains(category)) {
                        model.toggle(category, in: kind)
                    }
                }
            }
        }
        .kinCard()
    }
}

/// Wrapping horizontal layout for chips (SwiftUI `Layout`, iOS 16+).
public struct FlowLayout: Layout {
    var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += size.width + gap
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
