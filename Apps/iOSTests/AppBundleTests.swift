import Foundation
import HabitUI
@testable import SpacedHabits
import Testing

struct AppBundleTests {
    @Test func hostAppHasVersionAndBuildNumber() {
        let info = BuildInfo(infoDictionary: Bundle.main.infoDictionary)
        #expect(info.version != "?")
        #expect(info.build != "?")
        #expect(
            info.version != "1.0", "Info.plist must take MARKETING_VERSION, not XcodeGen's default"
        )
    }

    /// Background refresh reschedules notifications (DESIGN.md §8); iOS refuses unlisted task IDs.
    /// CloudKit's silent pushes wake the app to merge other devices' changes (§10).
    @Test func backgroundModesAreDeclared() {
        let ids =
            Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
                as? [String]
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(ids == ["ga.emira.spacedhabits.refresh"])
        #expect(modes == ["fetch", "remote-notification"])
    }

    /// §6: the widget extension is embedded, and widget taps open `spacedhabits://` links.
    @Test func widgetExtensionAndURLSchemeAreDeclared() throws {
        let plugIns = try #require(Bundle.main.builtInPlugInsURL)
        let widgets = try #require(
            Bundle(url: plugIns.appendingPathComponent("SpacedHabitsWidgets.appex"))
        )
        let point =
            (widgets
                .object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?[
                "NSExtensionPointIdentifier"
            ]
        #expect(point as? String == "com.apple.widgetkit-extension")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        #expect(types?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] } == [DeepLink.scheme])
    }

    /// §7: the watch app ships inside the iOS app and names it as its companion; §6: it carries the
    /// Smart Stack and complication widgets.
    @Test func watchAppIsEmbedded() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Watch/SpacedHabitsWatch.app")
        let watch = try #require(Bundle(url: url))
        #expect(watch.bundleIdentifier == "ga.emira.spacedhabits.watchkitapp")
        #expect(
            watch.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String
                == Bundle.main
                .bundleIdentifier
        )
        #expect(watch.object(forInfoDictionaryKey: "WKApplication") as? Bool == true)
        let plugIns = try #require(watch.builtInPlugInsURL)
        let widgets = try #require(
            Bundle(url: plugIns.appendingPathComponent("SpacedHabitsWatchWidgets.appex"))
        )
        #expect(widgets.bundleIdentifier == "ga.emira.spacedhabits.watchkitapp.widgets")
    }

    /// §6: App Shortcuts (Siri phrases) are extracted into the app's App Intents metadata.
    @Test func appShortcutsAreInTheMetadata() throws {
        let url = Bundle.main.bundleURL.appendingPathComponent(
            "Metadata.appintents/extract.actionsdata"
        )
        let json = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        let actions = (json["actions"] as? [String: Any]).map { Set($0.keys) }
        #expect(
            actions == [
                "AnswerHabitIntent", "LogHabitIntent", "DelayHabitIntent", "ReviewHabitsIntent",
            ]
        )
        #expect((json["autoShortcuts"] as? [Any])?.count == 3)
    }

    /// §2: every bundle ships a privacy manifest (no tracking, `UserDefaults` reasons only), and the app
    /// declares its encryption exempt so App Store Connect doesn't ask per build.
    @Test func privacyManifestsAndExportComplianceAreDeclared() throws {
        let app = Bundle.main.bundleURL
        let bundles = [
            app,
            app.appendingPathComponent("PlugIns/SpacedHabitsWidgets.appex"),
            app.appendingPathComponent("Watch/SpacedHabitsWatch.app"),
            app.appendingPathComponent(
                "Watch/SpacedHabitsWatch.app/PlugIns/SpacedHabitsWatchWidgets.appex"
            ),
        ]
        for bundle in bundles {
            let data = try Data(contentsOf: bundle.appendingPathComponent("PrivacyInfo.xcprivacy"))
            let manifest = try #require(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            #expect(manifest["NSPrivacyTracking"] as? Bool == false, "\(bundle.lastPathComponent)")
            let types = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])?
                .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
            #expect(
                types == ["NSPrivacyAccessedAPICategoryUserDefaults"], "\(bundle.lastPathComponent)"
            )
        }
        #expect(
            Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool
                == false
        )
    }

    /// Settings → About links to the same pages App Store Connect does (MARKETING.md).
    @Test func supportAndPrivacyLinksAreValid() {
        #expect(
            SettingsView.supportURL?.absoluteString
                == "https://emira.ga/projects/spaced-habits/support"
        )
        #expect(
            SettingsView.privacyPolicyURL?.absoluteString
                == "https://emira.ga/projects/spaced-habits/privacy"
        )
    }
}
