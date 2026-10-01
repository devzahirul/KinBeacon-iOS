import XCTest

/// Walks every screen of both roles and attaches a screenshot of each — used for the README gallery and as a
/// smoke test that every route renders. Export: `make screenshots`.
final class ScreenshotTests: KinBeaconUITestCase {
    func testParentScreens() {
        launch(role: "parent", quiet: false)
        XCTAssertTrue(app.buttons["map.details"].waitForExistence(timeout: 10))
        sleep(3) // let map tiles load
        snapshot("01-parent-map")

        app.buttons["map.details"].tap()
        XCTAssertTrue(app.navigationBars["Emma"].waitForExistence(timeout: 5))
        snapshot("02-parent-child-detail")

        tapTab("Controls")
        XCTAssertTrue(app.buttons["mode.school"].waitForExistence(timeout: 5))
        snapshot("03-parent-controls")
        app.buttons["mode.school"].tap()
        XCTAssertTrue(app.buttons["schedule.save"].waitForExistence(timeout: 5))
        snapshot("04-parent-school-schedule")

        tapTab("Activity")
        XCTAssertTrue(app.staticTexts["activity.total"].waitForExistence(timeout: 5))
        snapshot("05-parent-activity")

        tapTab("Family")
        app.buttons["family.member.Lucas"].tap()
        let alert = app.buttons["child.alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.tap()
        XCTAssertTrue(app.buttons["alert.fix"].waitForExistence(timeout: 5))
        snapshot("06-parent-safety-alert")
    }

    func testChildScreens() {
        launch(role: "child")
        XCTAssertTrue(app.buttons["home.requestTime"].waitForExistence(timeout: 10))
        snapshot("07-child-home")

        app.buttons["home.requestTime"].tap()
        XCTAssertTrue(app.buttons["request.send"].waitForExistence(timeout: 5))
        snapshot("08-child-request-time")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["home.checkIn"].tap()
        XCTAssertTrue(app.buttons["checkin.imOK"].waitForExistence(timeout: 5))
        app.buttons["checkin.imOK"].tap()
        snapshot("09-child-check-in")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["home.mode"].tap()
        XCTAssertTrue(app.staticTexts["shield.title"].waitForExistence(timeout: 5))
        snapshot("10-child-shield")

        tapTab("Activity")
        sleep(1)
        snapshot("11-child-activity")

        tapTab("Help")
        XCTAssertTrue(app.staticTexts["Everything is working"].waitForExistence(timeout: 5))
        snapshot("12-child-help")
    }
}
