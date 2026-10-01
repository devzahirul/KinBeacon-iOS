public import Domain

/// Demo/test provider: permission state is a value you can flip to exercise the "permission turned off" flows.
public actor SimulatedPermissionsProvider: PermissionsProviding {
    private var report: PermissionHealthReport

    public init(report: PermissionHealthReport = .healthy) {
        self.report = report
    }

    public func currentReport() -> PermissionHealthReport {
        report
    }

    public func request(_ kind: PermissionKind) -> PermissionState {
        report.states[kind] = .granted
        return .granted
    }

    public func set(_ kind: PermissionKind, to state: PermissionState) {
        report.states[kind] = state
    }
}
