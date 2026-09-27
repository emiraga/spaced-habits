import XCTest

/// First launch (DESIGN.md §5.1 screen 0): idea → first habit → notifications → Today with its card.
final class OnboardingUITests: UITestCase {
    func testFirstHabitFromOnboardingIsAskedAbout() {
        launch(resetData: true, onboarding: true)
        XCTAssertTrue(appears(app.staticTexts["The habit tracker that asks less the better you do."]))
        attachScreenshot("onboarding-idea")
        app.buttons["Continue"].tap()
        XCTAssertTrue(disappears(app.buttons["Continue"]))

        let addHabit = app.buttons["onboarding.addHabit"]
        XCTAssertFalse(addHabit.isEnabled)
        app.buttons["Read"].tap()
        XCTAssertEqual(app.textFields["Habit name"].value as? String, "Read")
        attachScreenshot("onboarding-first-habit")
        addHabit.tap()
        XCTAssertTrue(disappears(addHabit))

        XCTAssertTrue(appears(app.buttons["Allow notifications"]))
        attachScreenshot("onboarding-notifications")
        app.buttons["Not now"].tap()

        XCTAssertTrue(appears(app.navigationBars["Today"]))
        XCTAssertTrue(count(app.buttons.matching(identifier: "Yes"), equals: 1))
        XCTAssertTrue(appears(app.staticTexts["📚 Read"]))

        // Once per device: a relaunch goes straight to Today.
        app.terminate()
        app.launchArguments = ["-disableAnimations"]
        app.launch()
        XCTAssertTrue(appears(app.navigationBars["Today"]))
        XCTAssertFalse(app.buttons["Continue"].exists)
    }
}
