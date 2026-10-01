import XCTest

/// The real (non-demo) parent journey against the live backend: create an account, name the family, add a child and
/// get a pairing code, then delete the account (App Store guideline 5.1.1(v)). Leaves no family data behind.
/// Skipped automatically when the build has no backend credentials.
final class LiveAccountUITests: KinBeaconUITestCase {
    func testParentSignUpInviteAndDeleteAccount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-KinResetState", "YES", "-KinDisableAnimations", "YES"]
        app.launch()
        self.app = app

        XCTAssertTrue(app.buttons["onboarding.parent"].waitForExistence(timeout: 10))
        guard app.buttons["onboarding.demo"].exists else { throw XCTSkip("Build has no backend credentials") }
        app.buttons["onboarding.parent"].tap()

        let runID = UUID().uuidString.prefix(8).lowercased()
        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Review Parent")
        app.textFields["Email"].tap()
        app.textFields["Email"].typeText("ui-\(runID)@test.kinbeacon.app")
        app.secureTextFields["Password (8+ characters)"].tap()
        app.secureTextFields["Password (8+ characters)"].typeText("ui-\(runID)-password")
        snapshot("20-live-sign-up")
        app.buttons["onboarding.submitAccount"].tap()
        dismissSavePasswordPrompt()

        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 15), "account created → family step")
        app.buttons["onboarding.continue"].tap()
        // Permission priming for parents: location, then notifications.
        for step in ["location", "notifications"] {
            XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 15), "family created → \(step) priming")
            app.buttons["Not now"].tap()
        }

        let addChild = app.buttons["map.addChild"]
        XCTAssertTrue(addChild.waitForExistence(timeout: 15), "empty live family shows the add-child card")
        snapshot("21-live-empty-map")
        addChild.tap()
        let childName = app.textFields["invite.name"]
        XCTAssertTrue(childName.waitForExistence(timeout: 5))
        childName.tap()
        childName.typeText("Emma")
        app.buttons["invite.create"].tap()
        let code = app.staticTexts["invite.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15), "server returns a pairing code")
        XCTAssertEqual(code.label.filter(\.isNumber).count, 6)
        snapshot("22-live-pairing-code")
        app.buttons["Close"].tap()

        app.tabBars.buttons["Family"].tap()
        XCTAssertTrue(app.buttons["family.member.Emma"].waitForExistence(timeout: 10), "invited child is listed")
        app.buttons["family.settings"].tap()
        let delete = app.buttons["settings.deleteAccount"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.buttons["Delete account"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboarding.parent"].waitForExistence(timeout: 15), "deleting the account returns to onboarding")
    }

    /// iOS offers to save the new password in a system sheet (outside the app's process).
    private func dismissSavePasswordPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for candidate in [springboard.buttons["Not Now"], app.buttons["Not Now"]] where candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            return
        }
    }
}
