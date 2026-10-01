#if canImport(FamilyControls) && os(iOS)
    public import Domain
    public import ScreenTimeShared
    import DeviceActivity
    import FamilyControls
    import Foundation
    import KinCore
    import ManagedSettings

    /// Screen Time adapter (FamilyControls + ManagedSettings + DeviceActivity).
    ///
    /// Responsibilities are split across processes exactly as Apple designed them:
    ///
    ///  App (this type)            → authorization, persists `SharedPolicy`, (re)schedules DeviceActivity monitoring,
    ///                               applies the current state immediately.
    ///  DeviceActivityMonitor ext. → wakes at schedule boundaries (even when the app is terminated) and applies/clears
    ///                               shields via the same `ShieldEnforcer`.
    ///  ShieldConfiguration ext.   → renders "Instagram is unavailable right now".
    ///  ShieldAction ext.          → "Request 15 min" → queues a request for the app to send.
    public final class LiveScreenTimeController: ScreenTimeControlling, Sendable {
        private let policyStore: SharedPolicyStore
        private let enforcer = ShieldEnforcer()
        private let names: @Sendable () async -> (child: String, guardian: String)

        public init(
            policyStore: SharedPolicyStore = SharedPolicyStore(),
            names: @escaping @Sendable () async -> (child: String, guardian: String)
        ) {
            self.policyStore = policyStore
            self.names = names
        }

        public func authorizationState() async -> PermissionState {
            await MainActor.run {
                switch AuthorizationCenter.shared.authorizationStatus {
                case .denied: .denied
                case .notDetermined: .notDetermined
                // `.approved`, plus iOS 26.4's `.approvedWithDataAccess` (not nameable with an iOS 17 deployment target).
                default: .granted
                }
            }
        }

        /// `.child` authorization (child's device, Family Sharing) can only be revoked with the parent's Apple ID —
        /// the strong guarantee a parental-control app needs. `.individual` is the self-managed variant for teens/adults.
        public func requestAuthorization(as role: MemberRole) async throws {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: role == .child ? .child : .individual)
            } catch {
                Log.screenTime.error("FamilyControls authorization failed: \(error.localizedDescription, privacy: .public)")
                throw KinError.permissionDenied(.screenTime)
            }
        }

        public func apply(_ configuration: ControlsConfiguration) async throws {
            let (child, guardian) = await names()
            var policy = policyStore.loadPolicy() ?? SharedPolicy(
                configuration: configuration,
                childName: child,
                guardianName: guardian,
                updatedAt: .now
            )
            // Ignore stale pushes: an older revision must never overwrite a newer one.
            guard configuration.revision >= policy.configuration.revision || policy.configuration.childID != configuration.childID else {
                Log.screenTime.notice("Ignoring stale controls revision \(configuration.revision)")
                return
            }
            policy.configuration = configuration
            policy.childName = child
            policy.guardianName = guardian
            policy.updatedAt = .now
            try policyStore.save(policy)
            try schedule(ActivityPlan(configuration: configuration))
            enforcer.enforce(policy, at: .now)
        }

        public func grantExtraTime(_ grant: ExtraTimeGrant) async throws {
            guard var policy = policyStore.loadPolicy() else { return }
            policy.grant = grant
            try policyStore.save(policy)
            enforcer.enforce(policy, at: .now)

            // A one-off activity whose end re-applies the shields from the Monitor extension, even if the app is killed.
            let calendar = Calendar.current
            let center = DeviceActivityCenter()
            let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
            let schedule = DeviceActivitySchedule(
                intervalStart: calendar.dateComponents(components, from: grant.startsAt),
                intervalEnd: calendar.dateComponents(components, from: max(grant.endsAt, grant.startsAt.addingTimeInterval(15 * 60))),
                repeats: false
            )
            center.stopMonitoring([DeviceActivityName(ActivityNames.extraTime)])
            try center.startMonitoring(DeviceActivityName(ActivityNames.extraTime), during: schedule)
        }

        public func removeAllRestrictions() async {
            DeviceActivityCenter().stopMonitoring()
            enforcer.clearAll()
            policyStore.clearPolicy()
        }

        private func schedule(_ plan: ActivityPlan) throws {
            let center = DeviceActivityCenter()
            let wanted = Set(plan.entries.map { DeviceActivityName($0.name) })
            let stale = center.activities.filter { !wanted.contains($0) && $0.rawValue != ActivityNames.extraTime }
            center.stopMonitoring(stale)
            guard plan.fitsSystemLimit else {
                Log.screenTime.fault("Activity plan exceeds the 20-activity system limit (\(plan.entries.count))")
                throw KinError.unsupportedOnThisDevice
            }
            for entry in plan.entries {
                var start = entry.start.dateComponents
                var end = entry.end.dateComponents
                start.weekday = entry.weekday?.rawValue
                // Overnight windows end on the following weekday.
                end.weekday = entry.weekday.map { entry.end <= entry.start ? ($0.rawValue % 7) + 1 : $0.rawValue }
                let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
                try center.startMonitoring(DeviceActivityName(entry.name), during: schedule)
            }
            Log.screenTime.info("Scheduled \(plan.entries.count) device activities")
        }
    }
#endif
