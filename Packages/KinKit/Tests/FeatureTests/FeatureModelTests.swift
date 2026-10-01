@testable import AlertsFeature
@testable import CheckInFeature
@testable import ControlsFeature
@testable import DemoBackend
@testable import Domain
import Foundation
@testable import HelpFeature
@testable import OnboardingFeature
@testable import RequestTimeFeature
@testable import Session
import Testing
import TestSupport

/// View-model tests run against the real demo backend (fast beat) — the same integration the app uses.
@MainActor
@Suite("Feature view models")
struct FeatureModelTests {
    func demo(_ perspective: DemoBackend.Configuration.Perspective) -> DemoBackend {
        DemoBackend(configuration: .init(perspective: perspective, beat: .milliseconds(20), spontaneousEvents: false))
    }

    // MARK: Request more time

    @Test("Requesting time shows 'waiting', then 'approved' when the parent answers")
    func requestTimeFlow() async {
        let backend = demo(.child)
        let store = CompanionStore(service: backend)
        let storeTask = Task { await store.run() }
        defer { storeTask.cancel() }
        #expect(await waitUntilOnMain { store.dashboard != nil })

        let outbox = InMemoryOutbox()
        let actions = SyncEngineActions(outbox: outbox, service: backend)
        let model = RequestTimeModel(store: store, actions: actions)
        model.option = .thirtyMinutes
        model.message = "  Finishing my essay  "
        await model.send()

        guard case let .waiting(request) = model.phase else {
            Issue.record("Expected waiting, got \(model.phase)")
            return
        }
        #expect(request.message == "Finishing my essay")
        #expect(model.message.isEmpty)
        #expect(await waitUntilOnMain {
            if case .approved = model.phase {
                return true
            }
            return false
        })
    }

    @Test("Validation errors are shown, not sent")
    func requestTimeValidation() async {
        let backend = demo(.child)
        let store = CompanionStore(service: backend)
        // No dashboard loaded → no active mode → nothing to request.
        let model = RequestTimeModel(store: store, actions: SyncEngineActions(outbox: InMemoryOutbox(), service: backend))
        await model.send()
        #expect(model.phase == .failed(TimeRequestPolicy.Violation.noActiveMode.message))
    }

    // MARK: Check in

    @Test("Check-in requires a choice, then confirms")
    func checkIn() async {
        let backend = demo(.child)
        let model = CheckInModel(
            store: CompanionStore(service: backend),
            actions: SyncEngineActions(outbox: InMemoryOutbox(), service: backend)
        )
        await model.send()
        if case .failed = model.phase {} else {
            Issue.record("Expected failure without a selection")
        }
        model.selected = .onMyWay
        await model.send()
        guard case let .sent(checkIn) = model.phase else {
            Issue.record("Expected sent")
            return
        }
        #expect(checkIn.kind == .onMyWay)
        model.reset()
        #expect(model.phase == .composing)
    }

    // MARK: Controls

    @Test("Edits stay in the draft until saved; saving bumps the revision")
    func controlsSave() async throws {
        let model = ControlsModel(childID: DemoData.emmaID, service: demo(.parent))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(!model.hasChanges)
        let revision = try #require(model.saved?.revision)

        model.toggle(.saturday, in: .school)
        #expect(model.hasChanges)
        #expect(await model.save())
        #expect(model.saved?.revision == revision + 1)
        #expect(model.saved?.mode(.school)?.schedule.days.contains(.saturday) == true)
        #expect(model.savedConfirmation == 1)
    }

    @Test("A failed save rolls back and explains why")
    func controlsRollback() async {
        let service = FailingControls()
        let model = ControlsModel(childID: Fixtures.child, service: service)
        await model.load()
        model.toggle(.games, in: .school)
        #expect(await !(model.save()))
        #expect(model.saveError == .offline)
        #expect(model.saved == Fixtures.controls())
        model.discardChanges()
        #expect(!model.hasChanges)
    }

    @Test("A schedule can't lose its last day, and short windows are flagged")
    func scheduleGuards() async {
        let model = ControlsModel(childID: DemoData.emmaID, service: demo(.parent))
        await model.load()
        model.update(.homework) { $0.schedule.days = [.monday] }
        model.toggle(.monday, in: .homework)
        #expect(model.mode(.homework)?.schedule.days == [.monday])
        model.update(.homework) { $0.schedule.end = $0.schedule.start.addingMinutes(10) }
        #expect(model.scheduleWarning(for: .homework) != nil)
    }

    // MARK: Family store + alerts

    @Test("Family store tracks snapshots and pending requests")
    func familyStore() async throws {
        let backend = demo(.parent)
        let store = FamilyStore(repository: backend, feed: backend, controls: backend)
        let task = Task { await store.run() }
        defer { task.cancel() }
        #expect(await waitUntilOnMain { store.snapshot != nil })
        #expect(store.selectedChild?.name == "Emma")
        #expect(store.badgeCount == 1) // Lucas' location alert

        let request = TimeRequest(childID: DemoData.emmaID, option: .fifteenMinutes, createdAt: .now)
        try await backend.submit(request)
        #expect(await waitUntilOnMain { store.pendingRequests.count == 1 })
        try await store.respond(to: request.id, approve: false)
        #expect(store.pendingRequests.isEmpty)
    }

    @Test("Fixing a safety alert sends a command and resolves the alert")
    func safetyAlert() async throws {
        let backend = demo(.parent)
        let store = FamilyStore(repository: backend, feed: backend, controls: backend)
        let task = Task { await store.run() }
        defer { task.cancel() }
        #expect(await waitUntilOnMain { store.snapshot != nil })
        let alert = try #require(store.openAlerts.first)
        let model = SafetyAlertModel(alertID: alert.id, store: store, controls: backend)
        #expect(model.permission == .location)
        #expect(!model.isResolved)
        await model.fix()
        #expect(model.fixState == .sent)
        #expect(await waitUntilOnMain { model.isResolved })
    }

    // MARK: Onboarding & help

    @Test("Child onboarding pairs, then primes each permission in order")
    func childOnboarding() async {
        var finished: OnboardingModel.Result?
        let model = OnboardingModel(permissions: GrantingPermissions()) { finished = $0 }
        model.choose(.child)
        #expect(model.path == [.pairing])
        await model.submitPairingCode()
        #expect(model.pairingError != nil)
        model.pairingCode = "482913"
        await model.submitPairingCode()
        #expect(model.path.last == .permission(.location))
        await model.request(.location)
        model.skip(.notifications)
        #expect(model.path.last == .permission(.screenTime))
        await model.request(.screenTime)
        #expect(finished?.role == .child)
    }

    @Test("Parent onboarding names the family and asks only for notifications")
    func parentOnboarding() async {
        var finished: OnboardingModel.Result?
        let model = OnboardingModel(permissions: GrantingPermissions()) { finished = $0 }
        model.choose(.parent)
        model.familyName = "  The Parkers "
        model.submitFamilyName()
        #expect(model.path.last == .permission(.notifications))
        await model.request(.notifications)
        #expect(finished == OnboardingModel.Result(role: .parent, familyName: "The Parkers"))
    }

    @Test("Help reflects permission health and reports changes")
    func help() async {
        var reported: [PermissionHealthReport] = []
        var degraded = PermissionHealthReport.healthy
        degraded.states[.location] = .denied
        let permissions = MutablePermissions(degraded)
        let model = HelpModel(permissions: permissions) { reported.append($0) }
        await model.refresh()
        #expect(!model.isHealthy)
        await model.fix(.location)
        #expect(model.isHealthy)
        #expect(reported.count == 2)
    }
}

// MARK: - Test doubles

struct SyncEngineActions: CompanionActions {
    let outbox: InMemoryOutbox
    let service: any CompanionService

    func sendCheckIn(_ kind: CheckInKind, message: String?) async throws -> CheckIn {
        let checkIn = CheckIn(memberID: DemoData.emmaID, kind: kind, message: message, createdAt: .now)
        try await service.submit(checkIn)
        return checkIn
    }

    func requestExtraTime(_ option: ExtraTimeOption, message: String?, appName: String?) async throws -> TimeRequest {
        let request = TimeRequest(childID: DemoData.emmaID, option: option, message: message, appName: appName, createdAt: .now)
        try await service.submit(request)
        return request
    }

    func sendSOS() async throws -> SOSEvent {
        SOSEvent(memberID: DemoData.emmaID, location: nil, battery: nil, createdAt: .now)
    }
}

struct FailingControls: ParentControlService {
    func controls(for child: MemberID) async throws -> ControlsConfiguration {
        Fixtures.controls()
    }

    func save(_ configuration: ControlsConfiguration) async throws -> ControlsConfiguration {
        throw KinError.offline
    }

    func pendingRequests() async throws -> [TimeRequest] {
        []
    }

    func respond(to requestID: UUID, approve: Bool) async throws -> TimeRequest {
        throw KinError.notFound
    }

    func send(_ action: RemoteCommand.Action, to child: MemberID) async throws {}
    func resolveAlert(_ alertID: UUID) async throws {}
}

struct GrantingPermissions: PermissionsProviding {
    func currentReport() async -> PermissionHealthReport {
        .healthy
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        .granted
    }
}

actor MutablePermissions: PermissionsProviding {
    var report: PermissionHealthReport
    init(_ report: PermissionHealthReport) {
        self.report = report
    }

    func currentReport() -> PermissionHealthReport {
        report
    }

    func request(_ kind: PermissionKind) -> PermissionState {
        report.states[kind] = .granted
        return .granted
    }
}

extension TimeOfDay {
    func addingMinutes(_ minutes: Int) -> TimeOfDay {
        TimeOfDay(minutesSinceMidnight: minutesSinceMidnight + minutes)
    }
}
