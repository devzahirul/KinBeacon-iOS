import Domain
import Foundation
import KinCore

/// What this device is (parent/child) and its local preferences. Tiny and synchronous to read, so the root view
/// can pick the right UI on the very first frame without touching the database.
struct SessionSettings: Equatable {
    var role: MemberRole?
    var familyName: String
    var liveScreenTime: Bool

    private static let roleKey = "kin.session.role"
    private static let familyKey = "kin.session.familyName"
    private static let liveScreenTimeKey = "kin.session.liveScreenTime"

    static func load(from defaults: UserDefaults, options: LaunchOptions) -> SessionSettings {
        if options.resetState {
            [roleKey, familyKey, liveScreenTimeKey].forEach(defaults.removeObject(forKey:))
        }
        let forcedRole = options.role.map { $0 == .parent ? MemberRole.parent : .child }
        return SessionSettings(
            role: forcedRole ?? defaults.string(forKey: roleKey).flatMap(MemberRole.init(rawValue:)),
            familyName: defaults.string(forKey: familyKey) ?? "Our Family",
            liveScreenTime: defaults.bool(forKey: liveScreenTimeKey)
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(role?.rawValue, forKey: Self.roleKey)
        defaults.set(familyName, forKey: Self.familyKey)
        defaults.set(liveScreenTime, forKey: Self.liveScreenTimeKey)
    }
}
