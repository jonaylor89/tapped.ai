import XCTest

@MainActor
final class PremiumOnboardingTests: XCTestCase {
    private func app(premium: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = [
            "TAPPED_MOCK": "1",
            "TAPPED_MOCK_SIGNED_IN": "1",
            "TAPPED_MOCK_PREMIUM": premium ? "1" : "0",
        ]
        return app
    }

    func testProfileSetupEndsAtTheOnlyPurchaseGate() {
        let app = app()
        app.launchEnvironment["TAPPED_MOCK_ONBOARDING"] = "1"
        app.launch()
        let name = app.textFields["display name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        name.tap()
        name.typeText("Premium Test Artist")
        app.buttons["continue"].firstMatch.tap()
        let skip = app.buttons["skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        app.buttons["skip for now"].tap()
        XCTAssertTrue(app.staticTexts["your profile is ready"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.maps.firstMatch.exists)
        XCTAssertFalse(app.buttons["skip for now"].exists)
        snapshot("final onboarding step")
        let activate = app.buttons["activate-premium"]
        for _ in 0..<6 where !activate.isHittable { app.swipeUp() }
        XCTAssertTrue(activate.isEnabled)
        activate.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15))
    }

    func testReturningNonSubscriberResumesActivationAndCanRestore() {
        let app = app()
        app.launchEnvironment["TAPPED_MOCK_LINK"] = "https://app.tapped.ai/opportunity/op-friday-openers"
        app.launch()
        XCTAssertTrue(app.staticTexts["your profile is ready"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.maps.firstMatch.exists)
        let restore = app.buttons["already subscribed? restore purchases"]
        for _ in 0..<6 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        XCTAssertTrue(app.alerts["no purchases to restore"].waitForExistence(timeout: 5))
        app.alerts.buttons["ok"].tap()
        XCTAssertFalse(app.maps.firstMatch.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["your profile is ready"].waitForExistence(timeout: 15))
    }

    func testExistingSubscriberSkipsActivation() {
        let app = app(premium: true)
        app.launch()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["activate-premium"].exists)
    }

    func testActivationAtAccessibilitySize() {
        let app = app()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["your profile is ready"].waitForExistence(timeout: 15))
        snapshot("activation accessibility top")
        let restore = app.buttons["already subscribed? restore purchases"]
        for _ in 0..<12 where !restore.isHittable { app.swipeUp() }
        XCTAssertTrue(restore.isHittable)
        snapshot("activation accessibility controls")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
