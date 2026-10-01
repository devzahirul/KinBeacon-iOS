public import Foundation

/// Project URL + publishable key from Info.plist (fed by the git-ignored `Config/Supabase.local.xcconfig`).
/// When either is missing the app offers the on-device demo only.
public struct SupabaseConfiguration: Sendable, Equatable {
    public let url: URL
    /// The *publishable* key — designed to ship in apps; Row Level Security protects the data.
    public let publishableKey: String
    /// KinBeacon lives in its own Postgres schema so the project can be shared with other apps.
    public static let schema = "kinbeacon"

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }

    public init?(infoDictionary: [String: Any]?) {
        guard let host = (infoDictionary?["KinSupabaseHost"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (infoDictionary?["KinSupabaseKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty, !key.isEmpty, !host.contains("$("),
              let url = URL(string: "https://\(host)") else { return nil }
        self.init(url: url, publishableKey: key)
    }
}
