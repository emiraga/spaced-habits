/// Marketing version and build number read from an Info.plist dictionary.
public struct BuildInfo: Sendable, Equatable {
    public let version: String
    public let build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Missing keys fall back to "?" so a misconfigured target is visible rather than blank.
    public init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    public var displayString: String {
        String(localized: "Version \(version) (\(build))", bundle: .module)
    }
}
