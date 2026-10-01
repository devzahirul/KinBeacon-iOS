import Domain
import Foundation
@testable import OnboardingFeature
import Testing
import TestSupport

@MainActor
@Suite("Live onboarding (accounts)")
struct LiveOnboardingTests {
    @Test("Parent sign-up → family → location → notifications finishes with a live membership")
    func parentSignUp() async {
        let account = FakeAccount()
        var finished: OnboardingModel.Result?
        let model = OnboardingModel(permissions: AlwaysGranted(), account: account) { finished = $0 }
        #expect(model.supportsAccounts)
        model.choose(.parent)
        #expect(model.path == [.parentAccount])

        model.email = "not-an-email"
        await model.submitAccount()
        #expect(model.errorMessage != nil, "invalid form is rejected locally")
        #expect(await account.calls.isEmpty)

        model.parentName = "Sarah"
        model.email = "Sarah@Example.com "
        model.password = "correct horse"
        await model.submitAccount()
        #expect(model.path.last == .familyName)
        #expect(await account.calls == ["signUp:sarah@example.com"])

        model.familyName = "The Parkers"
        await model.submitFamilyName()
        #expect(model.path.last == .permission(.location), "parents share their location too")
        await model.request(.location)
        #expect(model.path.last == .permission(.notifications))
        await model.request(.notifications)
        #expect(finished?.isDemo == false)
        #expect(finished?.membership == FakeAccount.parentMembership)
    }

    @Test("Signing in to an existing family skips family creation")
    func parentSignIn() async {
        let account = FakeAccount(existingFamily: true)
        let model = OnboardingModel(permissions: AlwaysGranted(), account: account) { _ in }
        model.choose(.parent)
        model.isCreatingAccount = false
        model.email = "sarah@example.com"
        model.password = "password123"
        await model.submitAccount()
        #expect(model.path.last == .permission(.location))
    }

    @Test("A bad pairing code shows the server's reason and stays on the step")
    func pairingFailure() async {
        let account = FakeAccount(pairingError: .invalidPairingCode)
        let model = OnboardingModel(permissions: AlwaysGranted(), account: account) { _ in }
        model.choose(.child)
        model.pairingCode = "123 456"
        await model.submitPairingCode()
        #expect(model.errorMessage == KinError.invalidPairingCode.errorDescription)
        #expect(model.path == [.pairing])
    }

    @Test("Try the demo finishes immediately as a demo session")
    func demo() {
        var finished: OnboardingModel.Result?
        let model = OnboardingModel(permissions: AlwaysGranted(), account: FakeAccount()) { finished = $0 }
        model.chooseDemo()
        model.startDemo(as: .child)
        #expect(finished?.isDemo == true)
        #expect(finished?.role == .child)
    }
}

struct AlwaysGranted: PermissionsProviding {
    func currentReport() async -> PermissionHealthReport {
        .healthy
    }

    func request(_ kind: PermissionKind) async -> PermissionState {
        .granted
    }
}

actor FakeAccount: AccountService {
    static let parentMembership = FamilyMembership(memberID: "parent-1", familyID: "family-1", role: .parent)
    private(set) var calls: [String] = []
    let existingFamily: Bool
    let pairingError: KinError?

    init(existingFamily: Bool = false, pairingError: KinError? = nil) {
        self.existingFamily = existingFamily
        self.pairingError = pairingError
    }

    func restore() -> AccountState {
        .signedOut
    }

    func signUp(name: String, email: String, password: String) -> AccountState {
        calls.append("signUp:\(email)")
        return .signedInWithoutFamily
    }

    func signIn(email: String, password: String) -> AccountState {
        calls.append("signIn:\(email)")
        return existingFamily ? .member(Self.parentMembership) : .signedInWithoutFamily
    }

    func createFamily(name: String, parentName: String, relationship: String?) -> FamilyMembership {
        calls.append("createFamily:\(name)")
        return Self.parentMembership
    }

    func pairDevice(code: String, deviceModel: String) throws -> FamilyMembership {
        if let pairingError {
            throw pairingError
        }
        return FamilyMembership(memberID: "child-1", familyID: "family-1", role: .child)
    }

    func inviteChild(_ child: NewChild) -> ChildInvite {
        ChildInvite(code: "123456", memberID: "child-1", expiresAt: .now)
    }

    func refreshInvite(for member: MemberID) -> ChildInvite {
        ChildInvite(code: "654321", memberID: member, expiresAt: .now)
    }

    func registerPushToken(_ token: String, sandbox: Bool) {}
    func signOut() {}
    func deleteAccount() {}
}
