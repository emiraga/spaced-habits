import XCTest

/// Minimal app flows (DESIGN.md §14): answer a card, relaunch, see it persisted; a gap yields a count card.
@MainActor
final class TodayFlowUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Fresh store with the three sample habits (Gym, Read, Meditate), all due today.
    private func launchWithSampleHabits() {
        app.launchArguments = ["-resetData"]
        app.launch()
        openSettings()
        app.buttons["Add sample habits"].tap()
        app.buttons["Done"].tap()
    }

    private func openSettings() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Advance one day"].waitForExistence(timeout: 5))
    }

    private func count(_ query: XCUIElementQuery, equals expected: Int) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: query)], timeout: 5)
            == .completed
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

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
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(count(yesButtons, equals: 2))
        XCTAssertTrue(count(gymDone, equals: 1))
        attachScreenshot("today-after-relaunch")
    }

    func testGapProducesCountCard() {
        launchWithSampleHabits()
        openSettings()
        for _ in 0 ..< 3 {
            app.buttons["Advance one day"].tap()
        }
        app.buttons["Done"].tap()
        // Created three days ago and never answered: four uncovered days.
        let countPrompts = app.staticTexts.matching(identifier: "How many of the last 4 days?")
        XCTAssertTrue(count(countPrompts, equals: 3))
        attachScreenshot("today-count-cards")

        app.buttons["Most"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["3 of 4 days"].exists)
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(count(countPrompts, equals: 2))
    }
}
