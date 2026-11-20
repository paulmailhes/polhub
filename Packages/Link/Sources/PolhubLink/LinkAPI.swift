import Foundation

/// How Polhub on the iPhone reaches Polhub on the Mac (20/11). The Mac listens on its own loopback only; `tailscale
/// serve` publishes it in HTTPS on Paul's tailnet. Every request carries the token of a paired iPhone.
public enum LinkAPI {
    /// The version of these addresses: the iPhone says which one it speaks, the Mac refuses another.
    public static let version = 1
    /// The Mac's port on its loopback, published by `tailscale serve --https=8443 http://127.0.0.1:8790`.
    public static let port: UInt16 = 8790
    /// The HTTPS port `tailscale serve` publishes it on.
    public static let publishedPort = 8443

    /// The addresses, under `/v1`.
    public enum Path {
        public static let status = "/v1/status"
        public static let folders = "/v1/mail/folders"
        public static let threads = "/v1/mail/threads"
        public static let thread = "/v1/mail/thread"
        public static let file = "/v1/mail/file"
        public static let events = "/v1/calendar"
        public static let projects = "/v1/projects"
        public static let project = "/v1/project"
        public static let meetings = "/v1/meetings"
        public static let meeting = "/v1/meeting"
        // Writing (lot 3, 20/11): POST, a JSON body.
        public static let accounts = "/v1/mail/accounts"
        public static let reply = "/v1/mail/reply"
        public static let newMail = "/v1/mail/new"
        public static let sending = "/v1/mail/sending"
        public static let cancel = "/v1/mail/cancel"
        public static let colin = "/v1/colin"
        public static let colinUndo = "/v1/colin/undo"
        /// The iPhone's push token (20/11).
        public static let push = "/v1/push"
    }

    /// The header of the token: `Authorization: Bearer <token>`.
    public static let authorization = "Authorization"

    /// `Authorization`'s value for `token`.
    public static func bearer(_ token: String) -> String { "Bearer \(token)" }

    /// The token in an `Authorization` value, or nil.
    public static func token(fromAuthorization value: String?) -> String? {
        guard let value, value.hasPrefix("Bearer ") else { return nil }
        let token = String(value.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    // MARK: - Pairing

    /// The link the Mac shows as a QR code: `polhub://appairer?adresse=https%3A…&jeton=…`. The iPhone's camera opens it
    /// in the app, which keeps the token in its Keychain.
    public static func pairingURL(address: URL, token: String) -> URL {
        var components = URLComponents()
        components.scheme = "polhub"
        components.host = "appairer"
        components.queryItems = [URLQueryItem(name: "adresse", value: address.absoluteString), URLQueryItem(name: "jeton", value: token)]
        return components.url!
    }

    /// The address and the token of a pairing link; nil for any other link, or an address that is not HTTPS (or
    /// HTTP on the iPhone's own loopback, for the simulator).
    public static func pairing(from url: URL) -> (address: URL, token: String)? {
        guard url.scheme == "polhub", url.host == "appairer",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "adresse" })?.value, let address = URL(string: raw),
              let token = items.first(where: { $0.name == "jeton" })?.value, !token.isEmpty else { return nil }
        let loopback = address.host == "127.0.0.1" || address.host == "localhost"
        guard address.scheme == "https" || (address.scheme == "http" && loopback), address.host != nil else { return nil }
        return (address, token)
    }

    // MARK: - JSON

    /// Dates as ISO 8601 with their fraction of a second, both ways. A new coder each time: one is not shared between
    /// threads.
    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) {
                return date
            }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Date illisible : \(text)"))
        }
        return decoder
    }
}
