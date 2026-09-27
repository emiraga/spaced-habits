import XCTest

/// §13 M4 in the real UI: pick a parent in the editor, see the child card follow the parent's answer with
/// its context line, and have a loop refused with a readable message.
final class DependencyFlowUITests: UITestCase {
    func testGatedChildFollowsParentAndCyclesAreRefused() {
        launchWithSampleHabits()

        // Protein depends on Gym.
        app.buttons["Add habit"].tap()
        app.textFields["Name"].tap()
        app.textFields["Name"].typeText("Protein\n")
        app.buttons["🏋️ Gym"].tap()
        XCTAssertTrue(app.buttons["🏋️ Gym"].isSelected)
        app.swipeUp()
        attachScreenshot("editor-depends-on")
        app.buttons["Save"].tap()

        // Gym isn't answered yet, so Protein waits; answering Gym "Yes" brings its card in.
        let proteinCard = app.staticTexts["You did Gym today."]
        XCTAssertTrue(appears(app.buttons["Yes"].firstMatch))
        XCTAssertFalse(proteinCard.exists)
        app.buttons.matching(identifier: "Yes").firstMatch.tap()
        XCTAssertTrue(appears(proteinCard))
        attachScreenshot("today-gated-card")

        // Gym → Protein → Gym is refused in the editor.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gym,'")).firstMatch.tap()
        app.buttons["Edit"].tap()
        app.buttons["Protein"].tap()
        let refusal = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'that would make a loop'"))
        XCTAssertTrue(appears(refusal.firstMatch))
        XCTAssertFalse(app.buttons["Protein"].isSelected)
        app.swipeUp()
        attachScreenshot("editor-cycle-refused")
    }
}
