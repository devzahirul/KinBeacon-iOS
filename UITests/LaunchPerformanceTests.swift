import XCTest

/// Cold-launch time to first frame, measured by XCTest on the device (5 iterations + 1 warm-up).
/// Run in Release for representative numbers: `make perf`.
final class LaunchPerformanceTests: XCTestCase {
    @MainActor
    func testParentColdLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-KinRole", "parent", "-KinFastSimulation", "YES", "-KinQuietDemo", "YES"]
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) { app.launch() }
    }

    @MainActor
    func testChildColdLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-KinRole", "child", "-KinFastSimulation", "YES", "-KinQuietDemo", "YES"]
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) { app.launch() }
    }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }
}
