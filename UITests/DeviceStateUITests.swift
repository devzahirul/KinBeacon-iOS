import XCTest

/// Developer tooling: captures the current device state without resetting anything (run on demand).
final class DeviceStateUITests: KinBeaconUITestCase {
    func testCaptureChildActivity() throws {
        guard ProcessInfo.processInfo.environment["KIN_CAPTURE"] == "1" else { throw XCTSkip("Set TEST_RUNNER_KIN_CAPTURE=1") }
        let app = XCUIApplication()
        app.launch()
        self.app = app
        sleep(4)
        snapshot("state-launch")
        guard app.tabBars.buttons["Activity"].waitForExistence(timeout: 10) else { return }
        app.tabBars.buttons["Activity"].tap()
        sleep(6) // the report extension renders asynchronously
        snapshot("state-activity")
        app.tabBars.buttons["Help"].tap()
        sleep(3)
        snapshot("state-help")
    }
}
