import XCTest

/// Cold launch to the signed-in shell in mock mode (no network), so regressions in launch work show up in CI.
final class LaunchPerformanceTests: XCTestCase {
    private func mockApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TAPPED_MOCK"] = "1"
        app.launchEnvironment["TAPPED_MOCK_SIGNED_IN"] = "1"
        return app
    }

    @MainActor
    func testLaunchPerformance() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTApplicationLaunchMetric(waitUntilResponsive: true),
                // `LaunchSignposts.Interval.launch`: didFinishLaunching → shell's first frame.
                XCTOSSignpostMetric(subsystem: "com.intheloopstudio", category: "PointsOfInterest", name: "Launch"),
            ],
            options: options
        ) {
            mockApp().launch()
        }
    }
}
