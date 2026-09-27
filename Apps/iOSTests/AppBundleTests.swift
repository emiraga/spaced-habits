import Foundation
import HabitUI
import Testing

struct AppBundleTests {
    @Test func hostAppHasVersionAndBuildNumber() {
        let info = BuildInfo(infoDictionary: Bundle.main.infoDictionary)
        #expect(info.version != "?")
        #expect(info.build != "?")
    }
}
