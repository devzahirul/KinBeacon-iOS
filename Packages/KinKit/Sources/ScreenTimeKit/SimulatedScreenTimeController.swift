public import Domain
public import ScreenTimeShared
import Foundation
import KinCore

/// Simulator/demo implementation: FamilyControls authorization is unavailable in the simulator, so this keeps the
/// same observable behaviour (policy persisted for the shield preview, grants recorded) without touching the OS.
public actor SimulatedScreenTimeController: ScreenTimeControlling {
    private var state: PermissionState
    private let policyStore: SharedPolicyStore
    public private(set) var appliedRevision: Int?
    public private(set) var lastGrant: ExtraTimeGrant?

    public init(authorization: PermissionState = .granted, policyStore: SharedPolicyStore = SharedPolicyStore()) {
        state = authorization
        self.policyStore = policyStore
    }

    public func authorizationState() -> PermissionState {
        state
    }

    public func requestAuthorization(as role: MemberRole) throws {
        state = .granted
    }

    public func apply(_ configuration: ControlsConfiguration) throws {
        appliedRevision = configuration.revision
        var policy = policyStore.loadPolicy() ?? SharedPolicy(
            configuration: configuration,
            childName: "Emma",
            guardianName: "Mom",
            updatedAt: .now
        )
        policy.configuration = configuration
        policy.updatedAt = .now
        try policyStore.save(policy)
    }

    public func grantExtraTime(_ grant: ExtraTimeGrant) throws {
        lastGrant = grant
        guard var policy = policyStore.loadPolicy() else { return }
        policy.grant = grant
        try policyStore.save(policy)
    }

    public func removeAllRestrictions() {
        appliedRevision = nil
        policyStore.clearPolicy()
    }
}
