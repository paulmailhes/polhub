import Foundation

/// What a `meet.google.com` address says: which room, and which Google account opened it.
public struct MeetLink: Equatable, Sendable, Codable {
    /// `abc-defg-hij`, lowercased. Nil when the page is not a meeting room (landing page, lobby list…).
    public let code: String?
    /// Value of `?authuser=`, percent-decoded: an account index (`1`) or an address.
    public let authUser: String?

    public var isRoom: Bool { code != nil }

    public init(code: String?, authUser: String?) {
        self.code = code
        self.authUser = authUser
    }

    /// Returns nil when the host is not `meet.google.com`.
    public static func parse(_ urlString: String) -> MeetLink? {
        guard let components = URLComponents(string: urlString),
              components.host?.lowercased() == "meet.google.com"
        else { return nil }

        let segments = components.path.split(separator: "/").map { $0.lowercased() }
        let candidate = segments.first == "meet" ? segments.dropFirst().first : segments.first
        let code = candidate.flatMap { $0.wholeMatch(of: /[a-z]{3}-[a-z]{4}-[a-z]{3}/) != nil ? $0 : nil }
        let authUser = components.queryItems?.first { $0.name == "authuser" }?.value

        return MeetLink(code: code, authUser: authUser)
    }
}
