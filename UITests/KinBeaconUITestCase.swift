import XCTest

/// Shared launch configuration: demo data, simulated platform services, no animations.
@MainActor
class KinBeaconUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
    }

    @discardableResult
    func launch(role: String?, quiet: Bool = true, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-KinResetState",
            "YES",
            "-KinFastSimulation",
            "YES",
            "-KinDisableAnimations",
            "YES",
            "-KinQuietDemo",
            quiet ? "YES" : "NO",
        ]
        if let role {
            app.launchArguments += ["-KinRole", role]
        }
        app.launchArguments += extra
        app.launch()
        self.app = app
        return app
    }

    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func tapTab(_ title: String) {
        app.tabBars.buttons[title].tap()
    }
}
