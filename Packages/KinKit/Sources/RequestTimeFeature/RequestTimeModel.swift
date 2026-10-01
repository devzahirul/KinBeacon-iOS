public import Domain
public import Foundation
public import Observation
public import Session
import KinCore

@MainActor
@Observable
public final class RequestTimeModel {
    public enum Phase: Equatable {
        case composing
        case sending
        case waiting(TimeRequest)
        case approved(until: Date)
        case denied
        case failed(String)
    }

    public var option: ExtraTimeOption = .fifteenMinutes
    public var message = ""
    public let appName: String?
    private var localPhase: Phase = .composing
    private var sentRequestID: UUID?

    @ObservationIgnored public let store: CompanionStore
    @ObservationIgnored private let actions: any CompanionActions
    @ObservationIgnored private let now: () -> Date

    public init(appName: String? = nil, store: CompanionStore, actions: any CompanionActions, now: @escaping () -> Date = { Date() }) {
        self.appName = appName
        self.store = store
        self.actions = actions
        self.now = now
        // Re-opening the screen shows the request that is still waiting, not a blank form.
        if let pending = store.requests.first(where: { TimeRequestPolicy.resolveExpiry($0, now: now()).status == .pending }) {
            sentRequestID = pending.id
        }
    }

    /// The tracked request's live status (updated by the store's stream) wins over local state.
    public var phase: Phase {
        guard let sentRequestID, let request = store.requests.first(where: { $0.id == sentRequestID }) else { return localPhase }
        switch TimeRequestPolicy.resolveExpiry(request, now: now()).status {
        case .pending: return .waiting(request)
        case let .approved(until): return .approved(until: until)
        case .denied: return .denied
        case .expired: return .failed(String(localized: "Your request expired. You can send a new one."))
        }
    }

    public var activeMode: ActiveMode? {
        store.activeMode
    }

    public var guardianName: String {
        store.dashboard?.guardianName ?? String(localized: "your parent")
    }

    public var canSend: Bool {
        if case .sending = phase {
            return false
        }
        if case .waiting = phase {
            return false
        }
        return message.count <= TimeRequestPolicy.maxMessageLength
    }

    public func send() async {
        let history = store.requests
        if let violation = TimeRequestPolicy.validate(message: message, history: history, activeMode: activeMode, now: now()) {
            localPhase = .failed(violation.message)
            sentRequestID = nil
            return
        }
        localPhase = .sending
        do {
            let request = try await actions.requestExtraTime(
                option,
                message: TimeRequestPolicy.normalizedMessage(message),
                appName: appName
            )
            store.upsert(request)
            sentRequestID = request.id
            message = ""
        } catch {
            localPhase = .failed((error as? KinError)?.errorDescription ?? error.localizedDescription)
        }
    }

    public func startOver() {
        sentRequestID = nil
        localPhase = .composing
    }
}
