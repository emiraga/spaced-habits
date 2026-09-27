import HabitUI
import Testing

struct BuildInfoTests {
    @Test func readsVersionAndBuildFromInfoDictionary() {
        let info = BuildInfo(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "42"])
        #expect(info == BuildInfo(version: "0.1.0", build: "42"))
        #expect(info.displayString == "Version 0.1.0 (42)")
    }

    @Test func missingKeysAreVisible() {
        #expect(BuildInfo(infoDictionary: nil).displayString == "Version ? (?)")
    }
}
