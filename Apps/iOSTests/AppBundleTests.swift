import Foundation
import HabitUI
import Testing

struct AppBundleTests {
    @Test func hostAppHasVersionAndBuildNumber() {
        let info = BuildInfo(infoDictionary: Bundle.main.infoDictionary)
        #expect(info.version != "?")
        #expect(info.build != "?")
        #expect(info.version != "1.0", "Info.plist must take MARKETING_VERSION, not XcodeGen's default")
    }

    /// Background refresh reschedules notifications (DESIGN.md §8); iOS refuses unlisted task IDs.
    @Test func backgroundRefreshIsDeclared() {
        let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(ids == ["ga.emira.spacedhabits.refresh"])
        #expect(modes?.contains("fetch") == true)
    }

    /// §6: the widget extension is embedded, and widget taps open `spacedhabits://` links.
    @Test func widgetExtensionAndURLSchemeAreDeclared() throws {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let widgets = try #require(Bundle(url: plugIns.appendingPathComponent("SpacedHabitsWidgets.appex")))
        let point = (widgets
            .object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"]
        #expect(point as? String == "com.apple.widgetkit-extension")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        #expect(types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } == [DeepLink.scheme])
    }

    /// §6: App Shortcuts (Siri phrases) are extracted into the app's App Intents metadata.
    @Test func appShortcutsAreInTheMetadata() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Metadata.appintents/extract.actionsdata")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let actions = (json["actions"] as? [String: Any]).map { Set($0.keys) }
        #expect(actions == ["AnswerHabitIntent", "LogHabitIntent", "DelayHabitIntent", "ReviewHabitsIntent"])
        #expect((json["autoShortcuts"] as? [Any])?.count == 3)
    }
}
