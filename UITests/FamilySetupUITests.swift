import XCTest

/// Developer tooling, not part of the regular suite: sets up a real family across devices.
///   Parent (device):   TEST_RUNNER_KIN_SETUP_EMAIL=… TEST_RUNNER_KIN_SETUP_PASSWORD=… -only-testing:…/testSetUpParent
///   Child (simulator): TEST_RUNNER_KIN_PAIR_CODE=123456 -only-testing:…/testPairChild
/// Each test skips itself when its variables are missing.
final class FamilySetupUITests: KinBeaconUITestCase {
    private var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    func testSetUpParent() throws {
        guard let email = environment["KIN_SETUP_EMAIL"], let password = environment["KIN_SETUP_PASSWORD"] else {
            throw XCTSkip("Set TEST_RUNNER_KIN_SETUP_EMAIL / PASSWORD")
        }
        let app = launchFresh()
        app.buttons["onboarding.parent"].tap()
        let signIn = environment["KIN_SETUP_SIGNIN"] == "1"
        if signIn {
            XCTAssertTrue(app.buttons["Sign in"].waitForExistence(timeout: 5))
            app.buttons["Sign in"].tap()
        } else {
            let name = app.textFields["Your name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(environment["KIN_SETUP_NAME"] ?? "Sarah")
        }
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 5))
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText(email)
        app.secureTextFields["Password (8+ characters)"].tap()
        app.secureTextFields["Password (8+ characters)"].typeText(password)
        app.buttons["onboarding.submitAccount"].tap()
        tapSystemAlert(["Not Now"], timeout: 4)

        if !signIn {
            XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 15))
            app.buttons["onboarding.continue"].tap()
        }
        grantPermissionSteps(count: 2)

        XCTAssertTrue(app.tabBars.buttons["Family"].waitForExistence(timeout: 20))
        for (child, avatar, age) in [("Emma", 0, 10), ("Lucas", 1, 8)] {
            app.tabBars.buttons["Family"].tap()
            app.buttons["family.addChild"].tap()
            let field = app.textFields["invite.name"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(child)
            app.buttons["Avatar \(avatar + 1)"].tap()
            if age < 10 {
                app.buttons["Decrement"].firstMatch.tap(); app.buttons["Decrement"].firstMatch.tap()
            }
            app.buttons["invite.create"].tap()
            let code = app.staticTexts["invite.code"]
            XCTAssertTrue(code.waitForExistence(timeout: 15))
            print("KIN-CODE \(child) \(code.label.filter(\.isNumber))")
            snapshot("setup-code-\(child)")
            app.buttons["Close"].tap()
        }
    }

    func testPairChild() throws {
        guard let code = environment["KIN_PAIR_CODE"] else { throw XCTSkip("Set TEST_RUNNER_KIN_PAIR_CODE") }
        let app = launchFresh()
        app.buttons["onboarding.child"].tap()
        let field = app.textFields["onboarding.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        app.buttons["onboarding.join"].tap()
        grantPermissionSteps(count: 3)
        XCTAssertTrue(app.buttons["home.requestTime"].waitForExistence(timeout: 30), "paired child home")
        snapshot("setup-child-\(code)")
    }

    // MARK: Helpers

    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KinResetState", "YES"]
        app.launch()
        self.app = app
        XCTAssertTrue(app.buttons["onboarding.parent"].waitForExistence(timeout: 10))
        return app
    }

    /// Taps "Continue" on each priming screen and accepts the system prompt(s) that follow.
    private func grantPermissionSteps(count: Int) {
        for _ in 0 ..< count {
            let allow = app.buttons["onboarding.allow"]
            XCTAssertTrue(allow.waitForExistence(timeout: 20), "permission priming screen")
            allow.tap()
            // Location may show two prompts (While Using, then the Always upgrade).
            tapSystemAlert(["Allow While Using App", "Allow", "Change to Always Allow", "Allow Once"], timeout: 5)
            tapSystemAlert(["Change to Always Allow", "Allow While Using App", "Allow"], timeout: 3)
        }
    }

    private func tapSystemAlert(_ labels: [String], timeout: TimeInterval) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for label in labels {
                for scope in [springboard, app!] {
                    let button = scope.buttons[label]
                    if button.exists, button.isHittable {
                        button.tap()
                        return
                    }
                }
            }
            usleep(250_000)
        }
    }
}
