import Foundation

/// A Claude account as Vigie says it to its read token (0.36.0, 18/11): its name and how much of it is used — never
/// an address, a folder or a key.
struct ClaudeAccount: Decodable, Equatable, Identifiable, Sendable {
    struct Window: Decodable, Equatable, Sendable {
        var pct: Double?
        var resetsAt: Date?
    }

    struct Week: Decodable, Equatable, Sendable {
        var pct: Double?
        var resetsAt: Date?
        /// When the week would be full at the pace of the last day; `nil` when it holds.
        var fullAt: Date?
    }

    struct ModelWindow: Decodable, Equatable, Sendable {
        var label: String?
        var pct: Double?
        var resetsAt: Date?
    }

    struct Usage: Decodable, Equatable, Sendable {
        /// The window of five hours.
        var session: Window?
        var week: Week?
        /// A model's own week (« Fable »).
        var weekModel: ModelWindow?
        var observedAt: Date?
    }

    var id: String
    var label: String
    var isDefault: Bool?
    var connected: Bool?
    var usage: Usage?
}

/// An account's line, in words.
enum ClaudeAccountsText {
    struct Row: Equatable {
        var label: String
        /// The bar, 0 to 1; `nil` without a recent reading.
        var fraction: Double?
        /// « 71 % », « — ».
        var percent: String
        /// The model whose own limit is the tightest: « Fable ».
        var model: String?
        /// « tient · lun. 20 h », « plein jeu. 14 h », « plein · reprend lun. 20 h », « pas de relevé récent ».
        var verdict: String
        /// Full, or to be before the reset: said in the accent.
        var alarming: Bool
        /// The five hours, past three quarters only: « session 82 % · reprend à 23:40 ».
        var session: String?
    }

    /// The tightest quota counts: the week, or a model's own when it is higher.
    static func row(_ account: ClaudeAccount, now: Date, calendar: Calendar) -> Row {
        let usage = account.usage
        let week = usage?.week
        var pct = week?.pct
        var resets = week?.resetsAt
        // The week filling before its reset counts whatever window shows: Vigie projects the week only.
        let fullAt = week?.fullAt
        var model: String?
        if let other = usage?.weekModel, let otherPct = other.pct, otherPct > (pct ?? -1) {
            pct = otherPct
            resets = other.resetsAt
            model = other.label
        }
        var session: String?
        if let window = usage?.session, let used = window.pct, used >= 75 {
            session = "session \(percent(used))" + (window.resetsAt.map { " · reprend \(resumes($0, now: now, calendar: calendar))" } ?? "")
        }
        guard let pct else {
            return Row(label: account.label, fraction: nil, percent: "—", model: nil, verdict: "pas de relevé récent", alarming: false, session: session)
        }
        let verdict: String, alarming: Bool
        if pct >= 100 {
            verdict = "plein" + (resets.map { " · reprend \(moment($0, now: now, calendar: calendar))" } ?? "")
            alarming = true
        } else if let fullAt {
            verdict = "plein \(moment(fullAt, now: now, calendar: calendar))"
            alarming = true
        } else {
            verdict = "tient" + (resets.map { " · \(moment($0, now: now, calendar: calendar))" } ?? "")
            alarming = false
        }
        return Row(label: account.label, fraction: min(1, max(0, pct / 100)), percent: percent(pct), model: model, verdict: verdict,
                   alarming: alarming, session: session)
    }

    /// « 71 % », with the narrow space French puts before %.
    static func percent(_ pct: Double) -> String {
        "\(Int(pct.rounded()))\u{202F}%"
    }

    private static let weekdays = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]

    /// « 23:40 » today, « demain 9 h », « lun. 20 h », « lun. 20 h 15 ».
    static func moment(_ date: Date, now: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        let away = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if away == 0 { return "\(hour):\(minute < 10 ? "0" : "")\(minute)" }
        let clock = minute == 0 ? "\(hour) h" : "\(hour) h \(minute < 10 ? "0" : "")\(minute)"
        if away == 1 { return "demain \(clock)" }
        return "\(weekdays[((parts.weekday ?? 1) - 1 + 7) % 7]) \(clock)"
    }

    /// « à 23:40 » today, else as `moment` says it.
    static func resumes(_ date: Date, now: Date, calendar: Calendar) -> String {
        calendar.isDate(date, inSameDayAs: now) ? "à \(moment(date, now: now, calendar: calendar))" : moment(date, now: now, calendar: calendar)
    }
}

/// How a reading of Vigie went: said once in Polhub's log when it changes, never with the token.
enum VigieReading: Equatable, Sendable {
    case read(Int)
    case noToken
    case refused(Int)
    case unreachable
    case unreadable

    var said: String {
        switch self {
        case let .read(count): "comptes lus : \(count)"
        case .noToken: "pas de jeton"
        case let .refused(status): "refus \(status)"
        case .unreachable: "injoignable"
        case .unreadable: "réponse illisible"
        }
    }
}

/// Vigie, read by the app alone (0.36.0): `GET /api/v2/accounts` on this Mac, with the read token Vigie keeps for
/// another app. No file, no request; a refusal reads the token again once; anything else hides the section.
struct VigieAccountsReader: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    static let address = URL(string: "http://127.0.0.1:4777/api/v2/accounts")!
    static let header = "X-Vigie-Read-Token"

    let tokenFile: URL
    let fetch: Fetch

    init(tokenFile: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".vigie/data/read-token"),
         fetch: @escaping Fetch = VigieAccountsReader.live) {
        self.tokenFile = tokenFile
        self.fetch = fetch
    }

    /// No cache, no cookie: what Vigie says stays in memory.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    static let live: Fetch = { request in
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The token, when the file holds one: 64 hexadecimal characters.
    func token() -> String? {
        guard let text = try? String(contentsOf: tokenFile, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 64, token.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        return token
    }

    func accounts() async -> [ClaudeAccount]? {
        await read().accounts
    }

    func read() async -> (accounts: [ClaudeAccount]?, reading: VigieReading) {
        guard var token = token() else { return (nil, .noToken) }
        var retried = false
        while true {
            var request = URLRequest(url: Self.address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            request.httpMethod = "GET"
            request.setValue(token, forHTTPHeaderField: Self.header)
            guard let (data, status) = try? await fetch(request) else { return (nil, .unreachable) }
            if status == 401 || status == 403 {
                // Vigie may have made a new one: read once more, never in a loop.
                guard !retried, let again = self.token(), again != token else { return (nil, .refused(status)) }
                retried = true
                token = again
                continue
            }
            guard status == 200, let answer = try? Self.decoder.decode(Answer.self, from: data) else { return (nil, .unreadable) }
            let connected = answer.accounts.filter { $0.connected != false }
            return (connected, .read(connected.count))
        }
    }

    private struct Answer: Decodable {
        var accounts: [ClaudeAccount]
    }

    /// Vigie's dates: ISO 8601, with or without the milliseconds.
    static let decoder: JSONDecoder = {
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
    }()
}
