import XCTest

/// Critical parent journeys on the real app (demo backend, simulated platform services).
final class ParentFlowTests: KinBeaconUITestCase {
    func testApproveExtraTimeRequest() {
        launch(role: "parent", quiet: false)
        tapTab("Activity")
        let request = app.buttons["activity.pendingRequest"]
        XCTAssertTrue(request.waitForExistence(timeout: 10), "Emma's demo request should arrive")
        request.tap()
        app.buttons["request.approve"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Approved'")).firstMatch
            .waitForExistence(timeout: 5))
    }

    func testFixSafetyAlertFromChildDevice() {
        launch(role: "parent")
        tapTab("Family")
        app.buttons["family.member.Lucas"].tap()
        app.buttons["child.alert"].tap()
        app.buttons["alert.fix"].tap()
        let resolved = app.staticTexts["alert.title"]
        XCTAssertTrue(resolved.waitForExistence(timeout: 5))
        let fixed = NSPredicate(format: "label == 'Fixed — all good again'")
        expectation(for: fixed, evaluatedWith: resolved)
        waitForExpectations(timeout: 10)
    }

    func testEditSchoolScheduleAndSave() {
        launch(role: "parent")
        tapTab("Controls")
        app.buttons["mode.school"].tap()
        let save = app.buttons["schedule.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "Nothing to save before an edit")
        app.buttons["weekday.7"].tap() // Saturday
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["controls.activeMode"].waitForExistence(timeout: 5), "Save pops back to Controls")
    }

    func testRemoveChildFromFamily() {
        launch(role: "parent")
        tapTab("Family")
        let lucas = app.buttons["family.member.Lucas"]
        XCTAssertTrue(lucas.waitForExistence(timeout: 5))
        lucas.tap()
        app.buttons["More actions"].tap()
        app.buttons["child.remove"].tap()
        app.buttons["child.confirmRemove"].firstMatch.tap()
        XCTAssertTrue(app.buttons["family.member.Emma"].waitForExistence(timeout: 5), "back on the family list")
        XCTAssertFalse(app.buttons["family.member.Lucas"].exists, "Lucas is removed")
    }
}
