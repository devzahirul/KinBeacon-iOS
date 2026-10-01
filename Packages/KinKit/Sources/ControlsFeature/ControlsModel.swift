public import Domain
public import Foundation
public import Observation
import KinCore

/// Editing session for one child's controls: a saved copy and a draft. Saving is optimistic — the UI shows the new
/// state immediately and rolls back with an explanation if the server refuses.
@MainActor
@Observable
public final class ControlsModel {
    public enum Phase: Equatable {
        case loading
        case loaded
        case failed(KinError)
    }

    public let childID: MemberID
    public private(set) var phase: Phase = .loading
    public private(set) var saved: ControlsConfiguration?
    public var draft: ControlsConfiguration?
    public private(set) var isSaving = false
    public private(set) var saveError: KinError?
    public private(set) var savedConfirmation = 0

    @ObservationIgnored private let service: any ParentControlService
    @ObservationIgnored private let now: () -> Date

    public init(childID: MemberID, service: any ParentControlService, now: @escaping () -> Date = { Date() }) {
        self.childID = childID
        self.service = service
        self.now = now
    }

    public func loadIfNeeded() async {
        guard saved == nil else { return }
        await load()
    }

    public func load() async {
        phase = .loading
        do {
            let configuration = try await service.controls(for: childID)
            saved = configuration
            draft = configuration
            phase = .loaded
        } catch {
            phase = .failed(error as? KinError ?? .server(status: 0))
        }
    }

    public var hasChanges: Bool {
        draft != saved
    }

    @discardableResult
    public func save() async -> Bool {
        guard let draft, hasChanges else { return true }
        let previous = saved
        saved = draft
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            let confirmed = try await service.save(draft)
            saved = confirmed
            self.draft = confirmed
            savedConfirmation += 1
            return true
        } catch {
            saved = previous
            saveError = error as? KinError ?? .server(status: 0)
            return false
        }
    }

    public func discardChanges() {
        draft = saved
        saveError = nil
    }

    // MARK: Derived state (from the *saved* configuration — the draft isn't in force yet)

    public var activeMode: ActiveMode? {
        saved.flatMap { ModeResolver.activeMode(in: $0, at: now()) }
    }

    public var nextModeStart: (ControlModeKind, Date)? {
        guard let saved else { return nil }
        return saved.modes
            .filter(\.isEnabled)
            .compactMap { mode in mode.schedule.nextStart(after: now()).map { (mode.kind, $0) } }
            .min { $0.1 < $1.1 }
    }

    public func mode(_ kind: ControlModeKind) -> ModeSettings? {
        draft?.mode(kind)
    }

    // MARK: Draft editing

    public func update(_ kind: ControlModeKind, _ change: (inout ModeSettings) -> Void) {
        guard var mode = draft?.mode(kind) else { return }
        change(&mode)
        draft?.update(mode)
    }

    public func toggle(_ weekday: Weekday, in kind: ControlModeKind) {
        update(kind) { mode in
            if mode.schedule.days.contains(weekday) {
                // Never allow an empty schedule — it would silently disable the mode.
                guard mode.schedule.days.count > 1 else { return }
                mode.schedule.days.remove(weekday)
            } else {
                mode.schedule.days.insert(weekday)
            }
        }
    }

    public func toggle(_ category: ContentCategory, in kind: ControlModeKind) {
        update(kind) { mode in
            if mode.restrictedCategories.contains(category) {
                mode.restrictedCategories.remove(category)
            } else {
                mode.restrictedCategories.insert(category)
            }
        }
    }

    public func removeAllowedApp(_ app: AppDescriptor, in kind: ControlModeKind) {
        update(kind) { $0.allowedApps.apps.removeAll { $0.id == app.id } }
    }

    public func setLimit(_ minutes: Int, for app: AppDescriptor) {
        guard var limits = draft?.appLimits else { return }
        if let index = limits.firstIndex(where: { $0.app.id == app.id }) {
            limits[index].dailyMinutes = min(max(minutes, 15), 600)
        } else {
            limits.append(AppLimit(app: app, dailyMinutes: min(max(minutes, 15), 600)))
        }
        draft?.appLimits = limits
    }

    public func removeLimit(_ app: AppDescriptor) {
        draft?.appLimits.removeAll { $0.app.id == app.id }
    }

    /// Validation shown inline in the schedule editor.
    public func scheduleWarning(for kind: ControlModeKind) -> String? {
        guard let schedule = draft?.mode(kind)?.schedule else { return nil }
        if schedule.durationMinutes < 15 {
            return String(localized: "Schedules must be at least 15 minutes long.")
        }
        if kind == .school, schedule.spansMidnight {
            return String(localized: "School hours can’t run past midnight.")
        }
        return nil
    }
}

/// One `ControlsModel` per child, kept alive across the Controls navigation stack so the home screen and the
/// pushed editors share a single draft.
@MainActor
public final class ControlsModels {
    private var models: [MemberID: ControlsModel] = [:]
    private let make: (MemberID) -> ControlsModel

    public init(make: @escaping (MemberID) -> ControlsModel) {
        self.make = make
    }

    public func model(for child: MemberID) -> ControlsModel {
        if let model = models[child] {
            return model
        }
        let model = make(child)
        models[child] = model
        return model
    }
}
