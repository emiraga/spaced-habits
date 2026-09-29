import XCTest

/// Deleting a habit (DESIGN.md §13 M12). Archive, restore and the deletion cascade are `HabitUI` `OrganizeTests`.
final class OrganizeUITests: UITestCase {
    func testDeleteHabitFromEditorPersistsAcrossRelaunch() {
        launchWithSampleHabits()
        let readRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Read,'"))
        XCTAssertTrue(count(readRow, equals: 1))
        readRow.firstMatch.tap()
        app.buttons["Edit"].tap()
        scrollTo(app.buttons["Delete habit…"]).tap()
        app.buttons["Delete habit"].tap()

        // Back on Today without Read.
        XCTAssertTrue(appears(app.navigationBars["Today"]))
        XCTAssertTrue(count(readRow, equals: 0))
        XCTAssertTrue(count(app.buttons.matching(identifier: "Yes"), equals: 2))

        app.terminate()
        launch(resetData: false)
        XCTAssertTrue(count(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gym,'")), equals: 1))
        XCTAssertTrue(count(readRow, equals: 0))
    }
}
