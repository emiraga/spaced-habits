import XCTest

/// Minimal app flow (DESIGN.md §14): answer a card, relaunch, see it persisted, open Insights. Count cards
/// after a gap are `HabitUI` `AppModelTests.checkpointEightDays`; chart content is `HabitUI` `ChartTests`.
final class TodayFlowUITests: UITestCase {
    func testAnswerPersistsAcrossRelaunch() {
        launchWithSampleHabits()
        let yesButtons = app.buttons.matching(identifier: "Yes")
        XCTAssertTrue(count(yesButtons, equals: 3))
        attachScreenshot("today-three-cards")

        // Gym is high importance, so it is the first card.
        yesButtons.firstMatch.tap()
        XCTAssertTrue(count(yesButtons, equals: 2))
        let gymDone = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gym, Done'"))
        XCTAssertTrue(count(gymDone, equals: 1))

        app.terminate()
        launch(resetData: false)
        XCTAssertTrue(count(yesButtons, equals: 2))
        XCTAssertTrue(count(gymDone, equals: 1))
        attachScreenshot("today-after-relaunch")

        // One day of history: Insights explains why there are no charts yet (§12).
        app.buttons["Insights"].tap()
        XCTAssertTrue(appears(app.switches["Include paused days"]))
        XCTAssertTrue(appears(app.staticTexts["Charts appear after 7 days that aren't paused (1 so far)."]))
    }
}
