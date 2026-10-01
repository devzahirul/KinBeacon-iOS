public import Foundation

/// Identifiers shared by the app, its extensions, Info.plist and the entitlements files.
/// Keep in sync with `project.yml` (Info.plist keys) and the `.entitlements` files.
public enum AppConstants {
    public static let bundleID = "com.lynkto.kinbeacon"
    public static let appGroupID = "group.com.lynkto.kinbeacon"
    public static let urlScheme = "kinbeacon"

    /// BGAppRefreshTask: heartbeat, missed remote commands, permission-health report, outbox flush, history
    /// pruning. Must be listed in `BGTaskSchedulerPermittedIdentifiers`.
    public static let refreshTaskID = "com.lynkto.kinbeacon.refresh"

    /// The App Group container, falling back to Application Support when the entitlement is missing
    /// (unit tests, previews, unsigned CI builds).
    public static var sharedContainerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let fallback = URL.applicationSupportDirectory.appending(path: "KinBeaconShared", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
