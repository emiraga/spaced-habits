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
}
