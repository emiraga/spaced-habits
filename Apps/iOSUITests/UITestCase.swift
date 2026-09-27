import XCTest

/// Shared launch and helpers for the smoke flows. Every launch skips animations so taps don't wait on
/// sheet transitions.
@MainActor
class UITestCase: XCTestCase {
    let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Launches the app, from an empty store when `resetData` is set.
    func launch(resetData: Bool) {
        app.launchArguments = ["-disableAnimations"] + (resetData ? ["-resetData"] : [])
        app.launch()
    }

    /// Fresh store with the three sample habits (Gym, Read, Meditate), all due today.
    func launchWithSampleHabits() {
        launch(resetData: true)
        app.buttons["Settings"].tap()
        app.buttons["Add sample habits"].tap()
        app.buttons["Done"].tap()
    }

    /// Checks right away and only then polls: `XCTNSPredicateExpectation` waits a full second per poll.
    func count(_ query: XCUIElementQuery, equals expected: Int) -> Bool {
        if query.count == expected {
            return true
        }
        let predicate = NSPredicate(format: "count == %d", expected)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: query)], timeout: 5)
            == .completed
    }

    /// Like `waitForExistence`, which also polls once a second, but returns at once when already there.
    func appears(_ element: XCUIElement) -> Bool {
        element.exists || element.waitForExistence(timeout: 5)
    }

    func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
