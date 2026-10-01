public import Domain
public import Foundation
public import Observation
public import Session
import KinCore

/// Backs the child detail screen and its Location / Device / Safety sub-pages.
@MainActor
@Observable
public final class ChildProfileModel {
    public let memberID: MemberID
    public private(set) var today: ScreenTimeSummary?
    public private(set) var visits: [PlaceVisit] = []
    public private(set) var message: String?
    public var arrivalAlerts: [PlaceID: Bool] = [:]
    public var sosAlertsEnabled = true
    public var unusualActivityAlerts = true

    @ObservationIgnored public let store: FamilyStore
    @ObservationIgnored private let activity: any ActivityService
    @ObservationIgnored private let controls: any ParentControlService
    @ObservationIgnored private let now: () -> Date

    public init(
        memberID: MemberID,
        store: FamilyStore,
        activity: any ActivityService,
        controls: any ParentControlService,
        now: @escaping () -> Date = { Date() }
    ) {
        self.memberID = memberID
        self.store = store
        self.activity = activity
        self.controls = controls
        self.now = now
    }

    public var member: FamilyMember? {
        store.snapshot?.member(memberID)
    }

    public var status: MemberStatus? {
        store.snapshot?.status(memberID)
    }

    public var alerts: [SafetyAlert] {
        store.snapshot?.alerts(for: memberID) ?? []
    }

    public var activeMode: ActiveMode? {
        store.snapshot?.activeModes[memberID]
    }

    public var places: [Place] {
        store.snapshot?.places ?? []
    }

    public var currentPlace: Place? {
        store.snapshot?.place(status?.placeID)
    }

    public var isOnline: Bool {
        guard let status else { return false }
        return status.isOnline && now().timeIntervalSince(status.lastSeen) < 15 * 60
    }

    public func load() async {
        let date = now()
        async let summary = try? activity.screenTime(for: memberID, range: .day, anchor: date)
        async let visits = (try? activity.visits(for: memberID, on: date)) ?? []
        today = await summary
        self.visits = await visits
    }

    public func locateNow() async {
        await send(.locateNow, success: String(localized: "Requested a fresh location"))
    }

    public func requestCheckIn() async {
        await send(.requestCheckIn, success: String(localized: "Check-in request sent"))
    }

    private func send(_ action: RemoteCommand.Action, success: String) async {
        do {
            try await controls.send(action, to: memberID)
            message = success
        } catch {
            message = (error as? KinError)?.errorDescription ?? error.localizedDescription
        }
    }

    public func clearMessage() {
        message = nil
    }

    public func notifiesOnArrival(_ place: Place) -> Bool {
        arrivalAlerts[place.id] ?? place.notifiesOnArrival
    }
}
