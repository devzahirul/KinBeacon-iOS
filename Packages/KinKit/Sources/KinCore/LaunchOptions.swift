public import Foundation

/// Process-level switches parsed once at launch. UI tests and screenshot automation drive the app through these,
/// never through hidden debug UI.
///
///     -KinRole parent|child      skip onboarding and start in a role (demo data)
///     -KinResetState YES         wipe persisted state before launch
///     -KinFastSimulation YES     run the demo world ~8× faster (UI tests / screenshots)
///     -KinQuietDemo YES          no spontaneous demo events (fully deterministic UI tests)
///     -KinDisableAnimations YES  turn off UIView animations (faster, flake-free UI tests)
public struct LaunchOptions: Sendable, Equatable {
    public enum Role: String, Sendable { case parent, child }

    public var role: Role?
    public var resetState: Bool
    public var fastSimulation: Bool
    public var quietDemo: Bool
    public var disableAnimations: Bool
    public var apiBaseURL: URL?

    public init(
        role: Role? = nil,
        resetState: Bool = false,
        fastSimulation: Bool = false,
        quietDemo: Bool = false,
        disableAnimations: Bool = false,
        apiBaseURL: URL? = nil
    ) {
        self.role = role
        self.resetState = resetState
        self.fastSimulation = fastSimulation
        self.quietDemo = quietDemo
        self.disableAnimations = disableAnimations
        self.apiBaseURL = apiBaseURL
    }

    public init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(
            role: defaults.string(forKey: "KinRole").flatMap(Role.init(rawValue:)),
            resetState: defaults.bool(forKey: "KinResetState"),
            fastSimulation: defaults.bool(forKey: "KinFastSimulation"),
            quietDemo: defaults.bool(forKey: "KinQuietDemo"),
            disableAnimations: defaults.bool(forKey: "KinDisableAnimations"),
            apiBaseURL: (environment["KIN_API_BASE_URL"] ?? defaults.string(forKey: "KinAPIBaseURL")).flatMap(URL.init(string:))
        )
    }

    public var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
