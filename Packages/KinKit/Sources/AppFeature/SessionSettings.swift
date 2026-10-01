import Domain
import Foundation
import KinCore

/// What this device is (parent/child, demo/live) and its local preferences. One small JSON value in UserDefaults:
/// cheap and synchronous to read, so the root view picks the right UI on the very first frame, before any network.
struct SessionSettings: Equatable, Codable {
    var role: MemberRole?
    var isDemo = true
    var membership: FamilyMembership?
    var familyName = "Our Family"
    /// Demo on a real device: opt-in to real Screen Time enforcement.
    var liveScreenTime = false

    private static let key = "kin.session.v2"

    static func load(from defaults: UserDefaults, options: LaunchOptions) -> SessionSettings {
        if options.resetState {
            defaults.removeObject(forKey: key)
        }
        var settings = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(SessionSettings.self, from: $0) } ?? SessionSettings()
        if let forced = options.role {
            // UI tests and screenshots always run against the deterministic demo family.
            settings.role = forced == .parent ? .parent : .child
            settings.isDemo = true
        }
        return settings
    }

    func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
    }
}
