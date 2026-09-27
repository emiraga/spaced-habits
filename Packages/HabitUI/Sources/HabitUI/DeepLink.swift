import Foundation

/// `spacedhabits://` URLs, opened by widget taps (DESIGN.md §6).
public enum DeepLink: Hashable, Sendable {
    /// The Today screen.
    case today
    /// A habit's detail screen.
    case habit(UUID)

    public static let scheme = "spacedhabits"

    public init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        switch url.host() {
        case "today" where path.isEmpty:
            self = .today
        case "habit" where path.count == 1:
            guard let id = UUID(uuidString: path[0]) else { return nil }
            self = .habit(id)
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case let .habit(id):
            components.host = "habit"
            components.path = "/\(id.uuidString)"
        }
        guard let url = components.url else {
            preconditionFailure("URLComponents rejected \(components)")
        }
        return url
    }
}
