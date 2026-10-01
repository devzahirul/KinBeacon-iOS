import XCTest

/// Critical child journeys.
final class ChildFlowTests: KinBeaconUITestCase {
    func testRequestMoreTimeIsApproved() {
        launch(role: "child")
        app.buttons["home.requestTime"].tap()
        app.buttons["request.option.30"].tap()
        app.buttons["request.send"].tap()
        XCTAssertTrue(app.otherElements["request.approved"].waitForExistence(timeout: 10) || app.staticTexts["Approved!"]
            .waitForExistence(timeout: 1))
    }

    func testCheckIn() {
        launch(role: "child")
        app.buttons["home.checkIn"].tap()
        XCTAssertFalse(app.buttons["checkin.send"].isEnabled)
        app.buttons["checkin.imOK"].tap()
        app.buttons["checkin.send"].tap()
        XCTAssertTrue(app.staticTexts["Check-in sent"].waitForExistence(timeout: 5))
    }

    func testHoldToSendSOS() {
        launch(role: "child")
        app.buttons["home.sos"].tap()
        let button = app.otherElements["sos.button"].exists ? app.otherElements["sos.button"] : app.buttons["sos.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press(forDuration: 3.4)
        XCTAssertTrue(app.staticTexts["SOS sent"].waitForExistence(timeout: 5))
    }
}

final class OnboardingTests: KinBeaconUITestCase {
    func testParentOnboarding() {
        launch(role: nil)
        app.buttons["onboarding.parent"].tap()
        app.buttons["onboarding.continue"].tap()
        for _ in 0 ..< 2 { // location, notifications
            XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5))
            app.buttons["Not now"].tap()
        }
        XCTAssertTrue(app.buttons["map.details"].waitForExistence(timeout: 10))
    }

    func testChildOnboardingWithDemoCode() {
        launch(role: nil)
        app.buttons["onboarding.child"].tap()
        app.buttons["Use demo code"].tap()
        app.buttons["onboarding.join"].tap()
        for _ in 0 ..< 3 {
            XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 5))
            app.buttons["Not now"].tap()
        }
        XCTAssertTrue(app.buttons["home.requestTime"].waitForExistence(timeout: 10))
    }
}
