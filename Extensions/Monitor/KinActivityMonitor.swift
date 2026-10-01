import DeviceActivity
import Foundation
import KinCore
import ScreenTimeShared

/// Runs in its own process at DeviceActivity schedule boundaries — even when KinBeacon is terminated.
/// Memory ceiling is ~6 MB, which is why it links only `ScreenTimeShared` (no SwiftUI, no SwiftData).
final class KinActivityMonitor: DeviceActivityMonitor {
    private let store = SharedPolicyStore()
    private let enforcer = ShieldEnforcer()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // The callback can fire a few ms before the boundary; evaluate just inside the window.
        enforcer.enforce(store.loadPolicy(), at: Date().addingTimeInterval(30))
        Log.screenTime.info("Interval started: \(activity.rawValue, privacy: .public)")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        var policy = store.loadPolicy()
        if activity.rawValue == ActivityNames.extraTime, policy?.grant != nil {
            // Extra time is over: drop the grant so the active mode's shields come back.
            policy?.grant = nil
            if let policy {
                try? store.save(policy)
            }
        }
        enforcer.enforce(policy, at: Date().addingTimeInterval(1))
        Log.screenTime.info("Interval ended: \(activity.rawValue, privacy: .public)")
    }
}
