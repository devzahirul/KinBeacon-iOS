import XCTest

/// A child device joining a real family: the test plays the parent over REST, the app on the device is the child.
/// Regression test for the CLMonitor double-creation crash that happened right after pairing.
final class LiveChildPairingUITests: KinBeaconUITestCase {
    func testChildPairsAndStaysRunning() async throws {
        guard var parent = LiveBackendClient(bundle: Bundle(for: Self.self)) else { throw XCTSkip("No backend credentials") }
        let runID = UUID().uuidString.prefix(8).lowercased()
        try await parent.signUp(email: "ui-parent-\(runID)@test.kinbeacon.app", password: "ui-\(runID)-password")
        _ = try await parent.rpc("create_family", ["family_name": "UI \(runID)", "parent_name": "Sarah", "relationship": "Mom"])
        let invite = try await parent.rpc("create_child_invite", ["child_name": "Emma", "age": 10, "grade": 4]) as? [[String: Any]]
        let code = try XCTUnwrap(invite?.first?["code"] as? String)

        let app = XCUIApplication()
        app.launchArguments = ["-KinResetState", "YES", "-KinDisableAnimations", "YES"]
        app.launch()
        self.app = app
        XCTAssertTrue(app.buttons["onboarding.child"].waitForExistence(timeout: 10))
        app.buttons["onboarding.child"].tap()
        let field = app.textFields["onboarding.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        app.buttons["onboarding.join"].tap()

        // Permission priming: skip all three (the prompts themselves are system UI).
        for _ in 0 ..< 3 {
            XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 20), "paired → permission priming")
            app.buttons["Not now"].tap()
        }
        XCTAssertTrue(app.buttons["home.requestTime"].waitForExistence(timeout: 20), "child home loads with live data")
        // The crash happened a moment after the runtime started; stay alive for 10 s with location + realtime running.
        sleep(10)
        XCTAssertEqual(app.state, .runningForeground, "app must not crash after pairing")
        snapshot("23-live-child-home")

        let members = try await parent.select("members", query: "select=name,device_model,user_id&role=eq.child")
        XCTAssertEqual(members.first?["name"] as? String, "Emma")
        XCTAssertNotNil(members.first?["user_id"] as? String, "the parent sees the paired device")

        // Clean up: the child leaves in-app, then the parent deletes the family.
        app.tabBars.buttons["Settings"].tap()
        let delete = app.buttons["settings.deleteAccount"]
        for _ in 0 ..< 4 where !delete.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.buttons["Delete account"].firstMatch.tap()
        XCTAssertTrue(app.buttons["onboarding.child"].waitForExistence(timeout: 15))
        _ = try await parent.rpc("delete_my_account")
    }
}
