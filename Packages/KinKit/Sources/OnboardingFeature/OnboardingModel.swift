public import Domain
public import Observation
import Foundation
import KinCore

/// Onboarding state machine for both roles, live accounts and the demo.
///
/// Permissions are requested one at a time, each after an explanation screen — "priming" roughly doubles grant rates
/// and is what App Review expects for location "Always" and Screen Time.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Step: Hashable {
        case welcome
        case parentAccount
        case familyName
        case pairing
        case demoRole
        case permission(PermissionKind)
    }

    public struct Result: Equatable, Sendable {
        public var role: MemberRole
        public var familyName: String
        public var isDemo: Bool
        public var membership: FamilyMembership?
    }

    public var path: [Step] = []
    public var familyName = String(localized: "Our Family")
    public var relationship = String(localized: "Mom")
    public var parentName = ""
    public var email = ""
    public var password = ""
    public var isCreatingAccount = true
    public var pairingCode = ""
    public private(set) var errorMessage: String?
    public private(set) var isWorking = false
    public private(set) var role: MemberRole = .parent
    public private(set) var isDemo = true
    private var membership: FamilyMembership?

    @ObservationIgnored private let permissions: any PermissionsProviding
    @ObservationIgnored private let account: (any AccountService)?
    @ObservationIgnored private let deviceModel: String
    @ObservationIgnored private let finish: @MainActor (Result) -> Void

    public static let childPermissions: [PermissionKind] = [.location, .notifications, .screenTime]
    /// Parents share their own location with the family too (the map shows everyone).
    public static let parentPermissions: [PermissionKind] = [.location, .notifications]
    public static let relationships = [
        String(localized: "Mom"),
        String(localized: "Dad"),
        String(localized: "Parent"),
        String(localized: "Guardian"),
    ]

    public init(
        permissions: any PermissionsProviding,
        account: (any AccountService)? = nil,
        deviceModel: String = "iPhone",
        finish: @escaping @MainActor (Result) -> Void
    ) {
        self.permissions = permissions
        self.account = account
        self.deviceModel = deviceModel
        self.finish = finish
    }

    /// Live accounts are available when the build has backend credentials.
    public var supportsAccounts: Bool {
        account != nil
    }

    public func choose(_ role: MemberRole) {
        self.role = role
        isDemo = account == nil
        errorMessage = nil
        switch (role, isDemo) {
        case (.parent, false): path.append(.parentAccount)
        case (.parent, true): path.append(.familyName)
        case (.child, _): path.append(.pairing)
        }
    }

    public func chooseDemo() {
        path.append(.demoRole)
    }

    /// The demo skips accounts and permission prompts entirely.
    public func startDemo(as role: MemberRole) {
        finish(Result(role: role, familyName: String(localized: "Our Family"), isDemo: true, membership: nil))
    }

    // MARK: Parent account

    public var accountFormError: String? {
        if isCreatingAccount, parentName.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Enter your name.")
        }
        if !AccountValidation.isValidEmail(email) {
            return String(localized: "Enter a valid email address.")
        }
        if password.count < AccountValidation.minimumPasswordLength {
            return String(localized: "Use at least \(AccountValidation.minimumPasswordLength) characters for your password.")
        }
        return nil
    }

    public func submitAccount() async {
        guard let account, accountFormError == nil else {
            errorMessage = accountFormError
            return
        }
        await work {
            let email = self.email.trimmingCharacters(in: .whitespaces).lowercased()
            let state = self.isCreatingAccount
                ? try await account.signUp(
                    name: self.parentName.trimmingCharacters(in: .whitespaces),
                    email: email,
                    password: self.password
                )
                : try await account.signIn(email: email, password: self.password)
            switch state {
            case let .member(membership) where membership.role == .parent:
                self.membership = membership
                self.advance(after: nil)
            case .member:
                throw KinError.authentication(String(localized: "This account belongs to a child’s device."))
            case .signedInWithoutFamily:
                self.path.append(.familyName)
            case .signedOut:
                throw KinError.unauthorized
            }
        }
    }

    public func submitFamilyName() async {
        let name = familyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let account, !isDemo else {
            advance(after: nil)
            return
        }
        await work {
            let parentName = self.parentName.trimmingCharacters(in: .whitespaces)
            self.membership = try await account.createFamily(
                name: name,
                parentName: parentName.isEmpty ? self.relationship : parentName,
                relationship: self.relationship
            )
            self.advance(after: nil)
        }
    }

    // MARK: Child pairing

    public var isPairingCodeComplete: Bool {
        AccountValidation.isValidPairingCode(pairingCode)
    }

    public func submitPairingCode() async {
        guard isPairingCodeComplete else {
            errorMessage = String(localized: "Enter the 6-digit code shown on your parent’s phone.")
            return
        }
        guard let account, !isDemo else {
            errorMessage = nil
            advance(after: nil)
            return
        }
        await work {
            self.membership = try await account.pairDevice(code: self.pairingCode, deviceModel: self.deviceModel)
            self.advance(after: nil)
        }
    }

    // MARK: Permissions

    public func request(_ kind: PermissionKind) async {
        isWorking = true
        _ = await permissions.request(kind)
        isWorking = false
        advance(after: kind)
    }

    public func skip(_ kind: PermissionKind) {
        advance(after: kind)
    }

    private func advance(after kind: PermissionKind?) {
        errorMessage = nil
        let sequence = role == .parent ? Self.parentPermissions : Self.childPermissions
        let next: PermissionKind? = if let kind, let index = sequence.firstIndex(of: kind) {
            sequence.indices.contains(index + 1) ? sequence[index + 1] : nil
        } else {
            sequence.first
        }
        if kind != nil, next == nil {
            finish(Result(role: role, familyName: familyName.trimmingCharacters(in: .whitespaces), isDemo: isDemo, membership: membership))
        } else if let next {
            path.append(.permission(next))
        }
    }

    private func work(_ body: @escaping @MainActor () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await body()
        } catch {
            errorMessage = (error as? KinError)?.errorDescription ?? error.localizedDescription
        }
    }
}
