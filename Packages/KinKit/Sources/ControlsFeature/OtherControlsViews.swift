public import Domain
public import SwiftUI
import DesignSystem
import KinCore

/// Per-app daily limits.
public struct AppLimitsView: View {
    @Bindable var model: ControlsModel
    let catalog: [AppDescriptor]

    public init(model: ControlsModel, catalog: [AppDescriptor]) {
        self.model = model
        self.catalog = catalog
    }

    public var body: some View {
        List {
            Section {
                ForEach(model.draft?.appLimits ?? []) { limit in
                    HStack(spacing: KinSpace.sm) {
                        AppIconView(limit.app, size: 36)
                        VStack(alignment: .leading) {
                            Text(limit.app.name).font(.kinHeadline)
                            Text("\(KinFormat.duration(.seconds(limit.dailyMinutes * 60))) a day").font(.kinFootnote)
                                .foregroundStyle(KinColor.textSecondary)
                        }
                        Spacer()
                        Stepper(
                            "Limit",
                            value: Binding(get: { limit.dailyMinutes }, set: { model.setLimit($0, for: limit.app) }),
                            in: 15 ... 600,
                            step: 15
                        )
                        .labelsHidden()
                    }
                    .swipeActions { Button("Remove", role: .destructive) { model.removeLimit(limit.app) } }
                }
            } footer: {
                Text(
                    "When a limit is reached the app is shielded until midnight. \(model.draft.map { "Daily total: \(KinFormat.duration(.seconds($0.dailyScreenTimeMinutes * 60)))." } ?? "")"
                )
            }
            Section("Add a limit") {
                let limited = Set((model.draft?.appLimits ?? []).map(\.app.id))
                ForEach(catalog.filter { !limited.contains($0.id) }) { app in
                    Button { model.setLimit(60, for: app) } label: {
                        Label { Text(app.name) } icon: { AppIconView(app, size: 28) }
                    }
                }
            }
        }
        .navigationTitle("App Limits")
        .saveToolbar(model)
    }
}

/// Device-wide downtime window.
public struct DowntimeView: View {
    @Bindable var model: ControlsModel

    public init(model: ControlsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Downtime", isOn: Binding(
                    get: { model.draft?.downtime != nil },
                    set: { model.draft?.downtime = $0 ? WeeklySchedule(
                        start: TimeOfDay(hour: 20, minute: 30),
                        end: TimeOfDay(hour: 7),
                        days: Weekday.everyDay
                    ) : nil }
                ))
            } footer: {
                Text("During downtime only Always Allowed apps and phone calls are available.")
            }
            if let downtime = model.draft?.downtime {
                Section("Schedule") {
                    DatePicker(
                        "From",
                        selection: Binding(get: { downtime.start.date(on: .now) }, set: { model.draft?.downtime?.start = TimeOfDay($0) }),
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "To",
                        selection: Binding(get: { downtime.end.date(on: .now) }, set: { model.draft?.downtime?.end = TimeOfDay($0) }),
                        displayedComponents: .hourAndMinute
                    )
                }
            }
        }
        .tint(KinColor.brand)
        .navigationTitle("Downtime")
        .saveToolbar(model)
    }
}

/// Apps available in every mode.
public struct AlwaysAllowedView: View {
    @Bindable var model: ControlsModel
    @Environment(\.viewFactories) private var factories

    public init(model: ControlsModel) {
        self.model = model
    }

    public var body: some View {
        factories.appPicker(Binding(
            get: { model.draft?.alwaysAllowed ?? AppSelection() },
            set: { model.draft?.alwaysAllowed = $0 }
        ))
        .navigationTitle("Always Allowed")
        .saveToolbar(model)
    }
}

/// Safari / WebKit content filter level.
public struct WebFilterView: View {
    @Bindable var model: ControlsModel

    public init(model: ControlsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                Picker("Web content", selection: Binding(get: { model.draft?.webFilter ?? .off }, set: { model.draft?.webFilter = $0 })) {
                    ForEach(WebFilterLevel.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("Uses Screen Time’s built-in web content filter, which applies to Safari and every app that shows web pages.")
            }
        }
        .tint(KinColor.brand)
        .navigationTitle("Web Categories")
        .saveToolbar(model)
    }
}

private struct SaveToolbar: ViewModifier {
    @Bindable var model: ControlsModel
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task {
                        if await model.save() {
                            dismiss()
                        }
                    } }
                    .fontWeight(.semibold)
                    .disabled(!model.hasChanges || model.isSaving)
                }
            }
            .alert(
                model.saveError?.errorDescription ?? "",
                isPresented: Binding(get: { model.saveError != nil }, set: {
                    if !$0 {
                        model.discardChanges()
                    }
                })
            ) {}
            .onDisappear {
                if model.hasChanges, !model.isSaving {
                    model.discardChanges()
                }
            }
            .sensoryFeedback(.success, trigger: model.savedConfirmation)
    }
}

extension View {
    func saveToolbar(_ model: ControlsModel) -> some View {
        modifier(SaveToolbar(model: model))
    }
}
