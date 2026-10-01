public import Domain
public import Observation
import Foundation
import KinCore

/// Onboarding state machine. Permissions are requested one at a time, each after an explanation screen —
/// "priming" roughly doubles grant rates and is what App Review expects for location "Always".
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Hashable {
        case welcome
        case familyName
        case pairing
        case permission(PermissionKind)
    }

    public struct Result: Equatable, Sendable {
        public var role: MemberRole
        public var familyName: String
    }

    public var path: [Step] = []
    public var familyName = String(localized: "Our Family")
    public var pairingCode = ""
    public private(set) var pairingError: String?
    public private(set) var isRequesting = false
    public private(set) var role: MemberRole = .parent

    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let finish: @MainActor (Result) -> Void

    public static let childPermissions: [PermissionKind] = [.location, .notifications, .screenTime]
    public static let parentPermissions: [PermissionKind] = [.notifications]

    public init(permissions: any PermissionsProviding, finish: @escaping @MainActor (Result) -> Void) {
        self.permissions = permissions
        self.finish = finish
    }

    public func choose(_ role: MemberRole) {
        self.role = role
        path.append(role == .parent ? .familyName : .pairing)
    }

    public func submitFamilyName() {
        guard !familyName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        advance(after: nil)
    }

    public var isPairingCodeComplete: Bool {
        pairingCode.filter(\.isNumber).count == 6
    }

    public func submitPairingCode() async {
        guard isPairingCodeComplete else {
            pairingError = String(localized: "Enter the 6-digit code shown on your parent’s phone.")
            return
        }
        pairingError = nil
        // A production build exchanges the code for a device token + command-signing key here.
        advance(after: nil)
    }

    public func request(_ kind: PermissionKind) async {
        isRequesting = true
        _ = await permissions.request(kind)
        isRequesting = false
        advance(after: kind)
    }

    public func skip(_ kind: PermissionKind) {
        advance(after: kind)
    }

    private func advance(after kind: PermissionKind?) {
        let sequence = role == .parent ? Self.parentPermissions : Self.childPermissions
        let next: PermissionKind? = if let kind, let index = sequence.firstIndex(of: kind) {
            sequence.indices.contains(index + 1) ? sequence[index + 1] : nil
        } else {
            sequence.first
        }
        if kind != nil, next == nil {
            finish(Result(role: role, familyName: familyName.trimmingCharacters(in: .whitespaces)))
        } else if let next {
            path.append(.permission(next))
        }
    }
}
