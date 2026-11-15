import Foundation
import GoogleKit

/// The Gmail API, version 1, spoken to directly as the calendar's is (14/11). For now: what step 0 measures.
public enum GmailAPI {
    static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    public enum Format: String, Sendable {
        case minimal, metadata, full, raw
    }

    /// What a call costs in Google's quota units (table in force since May 2026); 6 000 a minute per account.
    public enum Cost {
        public static let profile = 1, label = 1, history = 2, messageList = 5, threadList = 10
        public static let metadata = 20, full = 60, batchModify = 50, untrash = 5, thread = 120, attachment = 20
        public static let sendAs = 1, draftCreate = 10, draftUpdate = 15, draftSend = 100, draftDelete = 10, draftList = 5, draftGet = 5
    }

    // MARK: - Requests

    static func request(_ path: String, _ items: [URLQueryItem] = [], accessToken: String, method: String = "GET", json: [String: Any]? = nil) -> URLRequest {
        var components = URLComponents(string: base + path)!
        if !items.isEmpty { components.queryItems = items }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        return request
    }

    public static func profileRequest(accessToken: String) -> URLRequest {
        request("/profile", accessToken: accessToken)
    }

    /// A label and its counts (`INBOX`, `CATEGORY_UPDATES`…).
    public static func labelRequest(accessToken: String, id: String) -> URLRequest {
        request("/labels/\(id)", accessToken: accessToken)
    }

    private static func listItems(query: String?, labelIDs: [String], pageToken: String?, maxResults: Int, includeSpamTrash: Bool) -> [URLQueryItem] {
        [URLQueryItem(name: "maxResults", value: String(maxResults))]
            + (query.map { [URLQueryItem(name: "q", value: $0)] } ?? [])
            + labelIDs.map { URLQueryItem(name: "labelIds", value: $0) }
            + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            + (includeSpamTrash ? [URLQueryItem(name: "includeSpamTrash", value: "true")] : [])
    }

    /// Message ids, the most recent first; spam and trash are left out by Gmail, unless `includeSpamTrash` (the
    /// folders « Spam » and « Corbeille », wave B).
    public static func messagesRequest(accessToken: String, query: String? = nil, labelIDs: [String] = [], pageToken: String? = nil,
                                       maxResults: Int = 500, includeSpamTrash: Bool = false) -> URLRequest {
        request("/messages", listItems(query: query, labelIDs: labelIDs, pageToken: pageToken, maxResults: maxResults, includeSpamTrash: includeSpamTrash),
                accessToken: accessToken)
    }

    public static func threadsRequest(accessToken: String, query: String? = nil, labelIDs: [String] = [], pageToken: String? = nil,
                                      maxResults: Int = 500, includeSpamTrash: Bool = false) -> URLRequest {
        request("/threads", listItems(query: query, labelIDs: labelIDs, pageToken: pageToken, maxResults: maxResults, includeSpamTrash: includeSpamTrash),
                accessToken: accessToken)
    }

    /// One message; in `metadata`, only the named headers come back.
    public static func messageRequest(accessToken: String, id: String, format: Format, headers: [String] = []) -> URLRequest {
        request("/messages/\(id)", [URLQueryItem(name: "format", value: format.rawValue)]
            + headers.map { URLQueryItem(name: "metadataHeaders", value: $0) }, accessToken: accessToken)
    }

    /// What changed since a cursor; a 404 means Gmail forgot it.
    public static func historyRequest(accessToken: String, startHistoryID: String, pageToken: String? = nil, maxResults: Int = 1) -> URLRequest {
        request("/history", [URLQueryItem(name: "startHistoryId", value: startHistoryID), URLQueryItem(name: "maxResults", value: String(maxResults))]
            + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? []), accessToken: accessToken)
    }

    /// A whole thread with its messages.
    public static func threadRequest(accessToken: String, id: String, format: Format) -> URLRequest {
        request("/threads/\(id)", [URLQueryItem(name: "format", value: format.rawValue)], accessToken: accessToken)
    }

    /// The addresses the mailbox sends as, with their name and Gmail's signature.
    public static func sendAsRequest(accessToken: String) -> URLRequest {
        request("/settings/sendAs", accessToken: accessToken)
    }

    /// A draft created (`draftID == nil`) or replaced, by an upload that carries the whole message, files
    /// included, and the thread it belongs to.
    public static func draftUploadRequest(accessToken: String, draftID: String?, raw: Data, threadID: String?) -> URLRequest {
        var url = "https://gmail.googleapis.com/upload/gmail/v1/users/me/drafts"
        if let draftID { url += "/\(draftID)" }
        var request = URLRequest(url: URL(string: url + "?uploadType=multipart")!)
        request.httpMethod = draftID == nil ? "POST" : "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let boundary = "polhub-envoi-\(UUID().uuidString)"
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var metadata: [String: Any] = [:]
        if let draftID { metadata["id"] = draftID }
        metadata["message"] = threadID.map { ["threadId": $0] } ?? [String: String]()
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body.append((try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])) ?? Data("{}".utf8))
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: message/rfc822\r\n\r\n".utf8))
        body.append(raw)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    /// Gmail sends the draft it holds; the draft disappears and a sent message takes its place.
    public static func draftSendRequest(accessToken: String, draftID: String) -> URLRequest {
        request("/drafts/send", accessToken: accessToken, method: "POST", json: ["id": draftID])
    }

    /// What Gmail holds of a draft now: its message's id changes with every version, wherever it was written.
    public static func draftRequest(accessToken: String, draftID: String) -> URLRequest {
        request("/drafts/\(draftID)", [URLQueryItem(name: "format", value: "minimal")], accessToken: accessToken)
    }

    public static func draftDeleteRequest(accessToken: String, draftID: String) -> URLRequest {
        request("/drafts/\(draftID)", accessToken: accessToken, method: "DELETE")
    }

    public static func draftsRequest(accessToken: String, pageToken: String? = nil) -> URLRequest {
        request("/drafts", [URLQueryItem(name: "maxResults", value: "500")] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? []),
                accessToken: accessToken)
    }

    /// The bytes of a file a message carries.
    public static func attachmentRequest(accessToken: String, messageID: String, attachmentID: String) -> URLRequest {
        request("/messages/\(messageID)/attachments/\(attachmentID)", accessToken: accessToken)
    }

    /// Labels added to and removed from these messages only: a gesture never reaches a message Paul has not seen.
    public static func batchModifyRequest(accessToken: String, ids: [String], add: [String], remove: [String]) -> URLRequest {
        request("/messages/batchModify", accessToken: accessToken, method: "POST",
                json: ["ids": ids, "addLabelIds": add, "removeLabelIds": remove])
    }

    public static func untrashRequest(accessToken: String, id: String) -> URLRequest {
        request("/messages/\(id)/untrash", accessToken: accessToken, method: "POST")
    }

    // MARK: - Answers

    public struct Profile: Decodable, Sendable, Equatable {
        public var emailAddress: String
        public var messagesTotal: Int
        public var threadsTotal: Int
        public var historyId: String
    }

    public struct Label: Decodable, Sendable, Equatable {
        public var id: String
        public var messagesTotal: Int?
        public var messagesUnread: Int?
        public var threadsTotal: Int?
        public var threadsUnread: Int?
    }

    /// A page of ids, of messages or of threads.
    public struct IDPage: Decodable, Sendable, Equatable {
        struct Item: Decodable, Sendable, Equatable { var id: String }
        var messages: [Item]?
        var threads: [Item]?
        public var nextPageToken: String?

        public var ids: [String] { (messages ?? threads ?? []).map(\.id) }
    }

    public struct Message: Decodable, Sendable, Equatable {
        public var id: String
        public var threadId: String?
        public var labelIds: [String]?
        public var sizeEstimate: Int?
        public var snippet: String?
        /// When Gmail received it, in milliseconds since 1970, as text.
        public var internalDate: String?
        public var payload: Part?
        /// The whole message as it travelled, in base64url (`format=raw` only).
        public var raw: String?
    }

    public struct SendAsList: Decodable, Sendable, Equatable {
        public struct Identity: Decodable, Sendable, Equatable {
            public var sendAsEmail: String
            public var displayName: String?
            public var signature: String?
            public var isPrimary: Bool?
            public var isDefault: Bool?
        }

        public var sendAs: [Identity]?
    }

    public struct Draft: Decodable, Sendable, Equatable {
        public struct Ref: Decodable, Sendable, Equatable {
            public var id: String
            public var threadId: String?
        }

        public var id: String
        public var message: Ref?
    }

    public struct DraftList: Decodable, Sendable, Equatable {
        public var drafts: [Draft]?
        public var nextPageToken: String?
    }

    public struct Thread: Decodable, Sendable, Equatable {
        public var id: String
        public var messages: [Message]?
    }

    /// What changed in a mailbox since a cursor.
    public struct HistoryPage: Decodable, Sendable, Equatable {
        public struct Change: Decodable, Sendable, Equatable {
            public var message: Message
        }

        public struct Record: Decodable, Sendable, Equatable {
            public var messagesAdded: [Change]?
            public var messagesDeleted: [Change]?
            public var labelsAdded: [Change]?
            public var labelsRemoved: [Change]?
        }

        public var history: [Record]?
        public var nextPageToken: String?
        /// The cursor to resume from next time.
        public var historyId: String?
    }

    public struct Part: Decodable, Sendable, Equatable {
        public var partId: String?
        public var mimeType: String?
        public var filename: String?
        public var headers: [Header]?
        public var body: Body?
        public var parts: [Part]?

        /// This part and every part under it.
        public var all: [Part] { [self] + (parts ?? []).flatMap(\.all) }

        public func header(_ name: String) -> String? {
            headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    public struct Header: Decodable, Sendable, Equatable {
        public var name: String
        public var value: String
    }

    public struct Body: Decodable, Sendable, Equatable {
        public var size: Int?
        /// The part's bytes, in base64url; absent when the part is an attachment to fetch apart.
        public var data: String?
        public var attachmentId: String?

        /// The decoded bytes of `data`.
        public var bytes: Data? {
            guard var text = data?.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") else { return nil }
            while text.count % 4 != 0 { text += "=" }
            return Data(base64Encoded: text)
        }
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw GoogleError.badAnswer }
    }

    /// What a refusal of Gmail's means. A quota refusal is passing: the same request can go again later.
    public static func error(status: Int, data: Data) -> GoogleError {
        let text = String(decoding: data, as: UTF8.self)
        switch status {
        case 401: return .expired
        case 429: return .rateLimited
        case 403 where text.contains("rateLimitExceeded") || text.contains("userRateLimitExceeded") || text.contains("RATE_LIMIT_EXCEEDED"):
            return .rateLimited
        case 403 where text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") || text.contains("insufficientPermissions"):
            return .missingScope(.gmailModify)
        case 403 where text.contains("accessNotConfigured") || text.contains("SERVICE_DISABLED"):
            return .refused("l'API Gmail n'est pas activée dans la console Google")
        case 404: return .notFound
        default: return .http(status)
        }
    }
}

/// Keeps the calls under Gmail's quota: so many units a minute, per account. Half the quota by default; the
/// other half stays for what Paul does himself.
public actor GmailPacer {
    let budget: Int
    let now: @Sendable () -> Date
    let sleep: @Sendable (TimeInterval) async -> Void
    private var spent: [(at: Date, units: Int)] = []

    public init(unitsPerMinute: Int = 3_000, now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.budget = unitsPerMinute
        self.now = now
        self.sleep = sleep
    }

    /// Returns when these units fit in the last minute's budget.
    public func take(_ units: Int) async {
        while true {
            let date = now()
            spent.removeAll { date.timeIntervalSince($0.at) >= 60 }
            if spent.isEmpty || spent.reduce(0, { $0 + $1.units }) + units <= budget {
                spent.append((date, units))
                return
            }
            await sleep(max(60 - date.timeIntervalSince(spent[0].at), 0.05))
        }
    }
}
