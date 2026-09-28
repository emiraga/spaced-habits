import XCTest

/// App Store screenshots of the watch app (`make screenshots-watch`), not a smoke test: `make test-ui` doesn't
/// run it. Reads `fixture.json` (`simulate dependent-pair --json` ending today) from `$SCREENSHOTS`
/// (`TEST_RUNNER_SCREENSHOTS` for xcodebuild) and writes the PNGs next to it.
@MainActor
final class WatchScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    /// Friendlier names than the simulation's, plus an emoji and color each.
    private static let looks: [String: [String: String]] = [
        "Gym": ["name": "Gym", "emoji": "🏋️", "colorHex": "#3366CC"],
        "Shake": ["name": "Protein shake", "emoji": "🥤", "colorHex": "#E0703A"],
    ]

    func testScreenshots() throws {
        continueAfterFailure = false
        let folder = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SCREENSHOTS"].map { URL(filePath: $0) },
            "Set TEST_RUNNER_SCREENSHOTS to the folder with fixture.json"
        )
        let fixture = folder.appending(path: "fixture.json")

        // The simulated run leaves nothing due today; a habit created today is asked about at once.
        try launch(fixture: styled(fixture, addingNewHabit: true))
        XCTAssertTrue(app.staticTexts["Done today?"].waitForExistence(timeout: 10))
        try save("1-today", in: folder)

        // The first swipes scroll the card; the next ones page to the habit list.
        let gym = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Gym'")).firstMatch
        for _ in 0 ..< 5 where !(gym.exists && gym.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        try save("2-habits", in: folder)

        gym.tap()
        let next = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Next check-in'")).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        try save("3-habit", in: folder)

        app.terminate()
        try launch(fixture: styled(fixture, addingNewHabit: false))
        XCTAssertTrue(app.staticTexts["Nothing to ask"].waitForExistence(timeout: 10))
        try save("4-done", in: folder)
    }

    private func launch(fixture: URL) {
        app.launchArguments = ["-resetData", "-importFixture", fixture.path(percentEncoded: false)]
        app.launch()
    }

    /// Writes a copy of the export with `looks` applied to every habit and habit revision, optionally plus
    /// a "Read" habit created today (a copy of the first habit, without its gate).
    private func styled(_ export: URL, addingNewHabit: Bool) throws -> URL {
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: export)) as? [String: Any])
        func restyle(_ habit: [String: Any]) throws -> [String: Any] {
            let name = try XCTUnwrap(habit["name"] as? String)
            return try habit.merging(XCTUnwrap(Self.looks[name], "No look for \(name)")) { $1 }
        }
        var habits = try XCTUnwrap(document["habits"] as? [[String: Any]]).map(restyle)
        var revisions = try XCTUnwrap(document["habitRevisions"] as? [[String: Any]]).map { revision in
            var revision = revision
            revision["habit"] = try restyle(XCTUnwrap(revision["habit"] as? [String: Any]))
            return revision
        }
        if addingNewHabit {
            let now = Date()
            var read = try XCTUnwrap(habits.first)
            read["id"] = UUID().uuidString
            read["name"] = "Read"
            read["emoji"] = "📚"
            read["colorHex"] = "#2E9E6A"
            read["dependencies"] = []
            read["createdAt"] = now.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            read["createdDay"] = now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
            habits.append(read)
            revisions.append(["id": UUID().uuidString, "editedAt": read["createdAt"] ?? "", "habit": read])
        }
        document["habits"] = habits
        document["habitRevisions"] = revisions
        let styled = export.deletingPathExtension().appendingPathExtension("styled.json")
        try JSONSerialization.data(withJSONObject: document).write(to: styled)
        return styled
    }

    private func save(_ name: String, in folder: URL) throws {
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: folder.appending(path: "\(name).png"))
    }
}
