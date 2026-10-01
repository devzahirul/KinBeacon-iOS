public import Domain
public import Foundation
public import Observation
public import Session
import KinCore

/// "Location permission turned off" → "Fix on child device".
///
/// The fix is a remote command (silent push) that makes the child's device show a notification deep-linking to
/// the right Settings pane — iOS doesn't let any app re-enable a permission on the user's behalf, and it shouldn't.
@MainActor
@Observable
public final class SafetyAlertModel {
    public enum FixState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    public let alertID: UUID
    public private(set) var fixState: FixState = .idle
    @ObservationIgnored public let store: FamilyStore
    @ObservationIgnored private let controls: any ParentControlService
    @ObservationIgnored private let original: SafetyAlert?

    public init(alertID: UUID, store: FamilyStore, controls: any ParentControlService) {
        self.alertID = alertID
        self.store = store
        self.controls = controls
        original = store.alert(alertID)
    }

    /// Falls back to the copy taken on open, so the screen can show "Fixed" after the alert leaves the snapshot.
    public var alert: SafetyAlert? {
        store.alert(alertID) ?? original
    }

    public var isResolved: Bool {
        original != nil && store.alert(alertID) == nil
    }

    public var child: FamilyMember? {
        alert.flatMap { store.snapshot?.member($0.memberID) }
    }

    public var permission: PermissionKind? {
        switch alert?.kind {
        case .locationPermissionOff: .location
        case .notificationsOff: .notifications
        case .deviceProtectionOff: .screenTime
        default: nil
        }
    }

    public func fix() async {
        guard let alert, let permission else { return }
        fixState = .sending
        do {
            try await controls.send(.fixPermissions(permission), to: alert.memberID)
            fixState = .sent
        } catch {
            fixState = .failed((error as? KinError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func dismissAlert() async {
        try? await controls.resolveAlert(alertID)
    }
}

/// Approve/decline an extra-time request (also reachable from the notification's action buttons).
@MainActor
@Observable
public final class TimeRequestModel {
    public enum Outcome: Equatable {
        case approved(until: Date)
        case denied
        case failed(String)
    }

    public let requestID: UUID
    public private(set) var isWorking = false
    public private(set) var outcome: Outcome?
    @ObservationIgnored public let store: FamilyStore
    @ObservationIgnored private let original: TimeRequest?

    public init(requestID: UUID, store: FamilyStore) {
        self.requestID = requestID
        self.store = store
        original = store.request(requestID)
    }

    public var request: TimeRequest? {
        store.request(requestID) ?? original
    }

    public var child: FamilyMember? {
        request.flatMap { store.snapshot?.member($0.childID) }
    }

    public func respond(approve: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await store.respond(to: requestID, approve: approve)
            switch result.status {
            case let .approved(until): outcome = .approved(until: until)
            case .denied: outcome = .denied
            case .expired: outcome = .failed(String(localized: "This request expired."))
            case .pending: outcome = nil
            }
        } catch {
            outcome = .failed((error as? KinError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
