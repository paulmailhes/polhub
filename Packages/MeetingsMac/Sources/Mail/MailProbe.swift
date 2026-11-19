import Domain
import Foundation
import GoogleKit

/// What step 0 measures on one mailbox before the mails are built (14/11). Numbers and codes only: never a
/// subject, a body or a correspondent's address.
public struct MailProbeReport: Codable, Sendable, Equatable {
    public struct Paced: Codable, Sendable, Equatable {
        public var reads = 0
        public var quotaRefusals = 0
        public var otherErrors = 0
        public var meanMilliseconds = 0
        /// Of the messages read in `metadata`, how many gave Gmail's authentication header back.
        public var withAuthenticationHeader = 0
    }

    public struct Sample: Codable, Sendable, Equatable {
        public var count = 0
        public var withHTML = 0
        public var plainOnly = 0
        public var charsets: [String: Int] = [:]
        public var undecodable = 0
        public var withInlineImages = 0
        public var withRemoteImages = 0
        public var withWebPOrAVIF = 0
        public var withAttachments = 0
        public var largestAttachmentBytes = 0
        public var htmlBytesMedian = 0
        public var htmlBytesMax = 0
        public var withAuthenticationHeader = 0
        public var dmarcPass = 0
        public var withListUnsubscribe = 0
        public var withOneClickUnsubscribe = 0
    }

    public var account: String
    public var startedAt: Date
    public var seconds = 0.0
    public var messagesTotal = 0
    public var threadsTotal = 0
    public var inboxThreads = 0
    public var inboxUnreadThreads = 0
    public var inboxThreadsOlderThanSixMonths = 0
    public var sixMonthsMessages = 0
    /// `false` when the count stopped at the cap: the mailbox holds more.
    public var sixMonthsCounted = true
    public var categories: [String: Int] = [:]
    public var historyCursorAccepted = false
    public var paced = Paced()
    public var sample = Sample()
    /// The steps that failed, as codes (`profile: expired`).
    public var errors: [String] = []

    public init(account: String, startedAt: Date) {
        self.account = account
        self.startedAt = startedAt
    }

    /// The report Paul and Claude read: one line per measure.
    public var text: String {
        var lines = ["Boîte \(account)", "  Messages : \(messagesTotal) · fils : \(threadsTotal)",
                     "  Boîte de réception : \(inboxThreads) fils, dont \(inboxUnreadThreads) non lus et \(inboxThreadsOlderThanSixMonths) de plus de six mois",
                     "  Six derniers mois : \(sixMonthsCounted ? "" : "plus de ")\(sixMonthsMessages) messages"]
        let names = ["CATEGORY_PERSONAL": "Principale", "CATEGORY_UPDATES": "Notifications", "CATEGORY_PROMOTIONS": "Promotions",
                     "CATEGORY_SOCIAL": "Réseaux sociaux", "CATEGORY_FORUMS": "Forums"]
        lines.append("  Catégories de Gmail : " + (categories.isEmpty ? "aucune lue" : names.keys.sorted().compactMap { key in
            categories[key].map { "\(names[key]!) \($0)" }
        }.joined(separator: ", ")))
        lines.append("  Point de reprise accepté par Gmail : \(historyCursorAccepted ? "oui" : "non")")
        lines.append("  Lecture cadencée : \(paced.reads) messages, \(paced.quotaRefusals) refus de quota, \(paced.otherErrors) autres erreurs, \(paced.meanMilliseconds) ms en moyenne ; en-tête d'authenticité présent sur \(paced.withAuthenticationHeader)")
        lines.append("  Échantillon de \(sample.count) mails : \(sample.withHTML) en HTML, \(sample.plainOnly) en texte seul, \(sample.undecodable) illisibles")
        lines.append("    Jeux de caractères : " + sample.charsets.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        lines.append("    Images jointes au mail : \(sample.withInlineImages) · images distantes : \(sample.withRemoteImages) · WebP ou AVIF : \(sample.withWebPOrAVIF)")
        lines.append("    Pièces jointes : \(sample.withAttachments) mails, la plus grosse \(sample.largestAttachmentBytes / 1_000) ko")
        lines.append("    HTML : médiane \(sample.htmlBytesMedian / 1_000) ko, maximum \(sample.htmlBytesMax / 1_000) ko")
        lines.append("    Authenticité : en-tête sur \(sample.withAuthenticationHeader), validée (dmarc) sur \(sample.dmarcPass)")
        lines.append("    Désabonnement : \(sample.withListUnsubscribe) mails, dont \(sample.withOneClickUnsubscribe) en un clic")
        lines.append("  Durée : \(Int(seconds)) s")
        if !errors.isEmpty { lines.append("  Erreurs : " + errors.joined(separator: " ; ")) }
        return lines.joined(separator: "\n")
    }
}

/// The measures themselves. `send` sends one request with the account's token and gives the answer's bytes.
public struct MailProbe: Sendable {
    public typealias Send = @Sendable (@escaping @Sendable (String) -> URLRequest) async throws -> Data

    public static let pacedReads = 200
    public static let sampleSize = 30
    static let authenticationHeader = "Authentication-Results"
    static let metadataHeaders = [authenticationHeader, "List-Unsubscribe", "List-Unsubscribe-Post"]
    static let categoryLabels = ["CATEGORY_PERSONAL", "CATEGORY_UPDATES", "CATEGORY_PROMOTIONS", "CATEGORY_SOCIAL", "CATEGORY_FORUMS"]

    let send: Send
    let pacer: GmailPacer
    let now: @Sendable () -> Date
    /// How many pages of 500 ids a count may read.
    let maxPages: Int

    public init(send: @escaping Send, pacer: GmailPacer = GmailPacer(), now: @escaping @Sendable () -> Date = { Date() }, maxPages: Int = 100) {
        self.send = send
        self.pacer = pacer
        self.now = now
        self.maxPages = maxPages
    }

    func get<T: Decodable & Sendable>(_ type: T.Type, cost: Int, _ build: @escaping @Sendable (String) -> URLRequest) async throws -> T {
        await pacer.take(cost)
        return try GmailAPI.decode(type, from: try await send(build))
    }

    static func code(_ error: Error) -> String {
        switch error as? GoogleError {
        case .expired: "expired"
        case .rateLimited: "rateLimited"
        case .notFound: "notFound"
        case .missingScope: "missingScope"
        case .http(let status): "http \(status)"
        case .refused: "refused"
        case .badAnswer: "badAnswer"
        default: "error"
        }
    }

    /// Counts the ids of a search, page by page; `complete` is false when the cap stopped it.
    func count(threads: Bool, query: String?, labelIDs: [String] = []) async throws -> (count: Int, complete: Bool, first: [String]) {
        var total = 0, token: String?, first: [String] = []
        for page in 0..<maxPages {
            let pageToken = token
            let ids = try await get(GmailAPI.IDPage.self, cost: threads ? GmailAPI.Cost.threadList : GmailAPI.Cost.messageList) { access in
                threads ? GmailAPI.threadsRequest(accessToken: access, query: query, labelIDs: labelIDs, pageToken: pageToken)
                        : GmailAPI.messagesRequest(accessToken: access, query: query, labelIDs: labelIDs, pageToken: pageToken)
            }
            if page == 0 { first = ids.ids }
            total += ids.ids.count
            token = ids.nextPageToken
            if token == nil { return (total, true, first) }
        }
        return (total, false, first)
    }

    public func run(account: String, progress: @escaping @Sendable (String) -> Void = { _ in }) async -> MailProbeReport {
        let started = now()
        var report = MailProbeReport(account: account, startedAt: started)
        func step(_ name: String, _ body: () async throws -> Void) async {
            progress(name)
            do { try await body() } catch { report.errors.append("\(name) : \(Self.code(error))") }
        }

        var cursor: String?
        await step("profil") {
            let profile = try await get(GmailAPI.Profile.self, cost: GmailAPI.Cost.profile) { GmailAPI.profileRequest(accessToken: $0) }
            report.messagesTotal = profile.messagesTotal
            report.threadsTotal = profile.threadsTotal
            cursor = profile.historyId
        }
        // Without the profile, nothing else will answer either (API not enabled, access refused).
        guard report.errors.isEmpty else {
            report.seconds = now().timeIntervalSince(started)
            return report
        }
        await step("boîte de réception") {
            let inbox = try await get(GmailAPI.Label.self, cost: GmailAPI.Cost.label) { GmailAPI.labelRequest(accessToken: $0, id: "INBOX") }
            report.inboxThreads = inbox.threadsTotal ?? 0
            report.inboxUnreadThreads = inbox.threadsUnread ?? 0
            report.inboxThreadsOlderThanSixMonths = try await count(threads: true, query: "in:inbox older_than:180d").count
        }
        var recent: [String] = []
        await step("six derniers mois") {
            let counted = try await count(threads: false, query: "newer_than:180d")
            report.sixMonthsMessages = counted.count
            report.sixMonthsCounted = counted.complete
            recent = counted.first
        }
        await step("catégories") {
            for id in Self.categoryLabels {
                let label = try await get(GmailAPI.Label.self, cost: GmailAPI.Cost.label) { GmailAPI.labelRequest(accessToken: $0, id: id) }
                report.categories[id] = label.messagesTotal ?? 0
            }
        }
        await step("point de reprise") {
            guard let cursor else { return }
            await pacer.take(GmailAPI.Cost.history)
            _ = try await send { GmailAPI.historyRequest(accessToken: $0, startHistoryID: cursor) }
            report.historyCursorAccepted = true
        }
        progress("lecture cadencée")
        report.paced = await paced(Array(recent.prefix(Self.pacedReads)))
        await step("échantillon") {
            let inbox = try await get(GmailAPI.IDPage.self, cost: GmailAPI.Cost.messageList) {
                GmailAPI.messagesRequest(accessToken: $0, labelIDs: ["INBOX"], maxResults: Self.sampleSize)
            }
            var messages: [GmailAPI.Message] = []
            for id in inbox.ids.prefix(Self.sampleSize) {
                if let message = try? await get(GmailAPI.Message.self, cost: GmailAPI.Cost.full, { GmailAPI.messageRequest(accessToken: $0, id: id, format: .full) }) {
                    messages.append(message)
                }
            }
            report.sample = Self.sample(messages)
        }
        report.seconds = now().timeIntervalSince(started)
        return report
    }

    /// Reads these messages in `metadata`, four at a time, under the quota: do refusals come anyway?
    func paced(_ ids: [String]) async -> MailProbeReport.Paced {
        enum Outcome: Sendable {
            case read(authenticated: Bool, milliseconds: Double), quota, other
        }
        var result = MailProbeReport.Paced()
        var milliseconds = 0.0
        await withTaskGroup(of: Outcome.self) { group in
            var remaining = ids[...]
            func add() {
                guard let id = remaining.popFirst() else { return }
                group.addTask {
                    await pacer.take(GmailAPI.Cost.metadata)
                    let start = Date()
                    do {
                        let data = try await send { GmailAPI.messageRequest(accessToken: $0, id: id, format: .metadata, headers: Self.metadataHeaders) }
                        let message = try GmailAPI.decode(GmailAPI.Message.self, from: data)
                        return .read(authenticated: message.payload?.header(Self.authenticationHeader) != nil,
                                     milliseconds: Date().timeIntervalSince(start) * 1_000)
                    } catch {
                        return error as? GoogleError == .rateLimited ? .quota : .other
                    }
                }
            }
            for _ in 0..<4 { add() }
            while let outcome = await group.next() {
                switch outcome {
                case .read(let authenticated, let time):
                    result.reads += 1
                    milliseconds += time
                    if authenticated { result.withAuthenticationHeader += 1 }
                case .quota: result.quotaRefusals += 1
                case .other: result.otherErrors += 1
                }
                add()
            }
        }
        result.meanMilliseconds = result.reads > 0 ? Int(milliseconds / Double(result.reads)) : 0
        return result
    }

    /// What a few whole messages are made of. Only counts leave this function.
    static func sample(_ messages: [GmailAPI.Message]) -> MailProbeReport.Sample {
        var sample = MailProbeReport.Sample()
        var htmlSizes: [Int] = []
        for message in messages {
            guard let payload = message.payload else { continue }
            sample.count += 1
            let parts = payload.all
            let html = parts.first { $0.mimeType == "text/html" && ($0.filename ?? "").isEmpty }
            let plain = parts.first { $0.mimeType == "text/plain" && ($0.filename ?? "").isEmpty }
            if html != nil { sample.withHTML += 1 } else if plain != nil { sample.plainOnly += 1 }
            if let body = html ?? plain {
                let charset = Self.charset(of: body)
                sample.charsets[charset, default: 0] += 1
                if let bytes = body.body?.bytes, let text = Self.text(bytes, charset: charset) {
                    if html != nil {
                        htmlSizes.append(bytes.count)
                        let lower = text.lowercased()
                        if lower.contains("cid:") { sample.withInlineImages += 1 }
                        if lower.range(of: #"<img[^>]+src\s*=\s*["']?https?://"#, options: .regularExpression) != nil { sample.withRemoteImages += 1 }
                        if lower.range(of: #"\.(webp|avif)\b"#, options: .regularExpression) != nil { sample.withWebPOrAVIF += 1 }
                    }
                } else {
                    sample.undecodable += 1
                }
            }
            let attachments = parts.filter { !($0.filename ?? "").isEmpty && $0.body?.attachmentId != nil }
            if !attachments.isEmpty {
                sample.withAttachments += 1
                sample.largestAttachmentBytes = max(sample.largestAttachmentBytes, attachments.compactMap { $0.body?.size }.max() ?? 0)
            }
            if let authentication = payload.header(authenticationHeader) {
                sample.withAuthenticationHeader += 1
                // As the app reads it (audit of 19/11): Gmail's own verdict, for the From's domain.
                if MailParser.authenticated(authentication, from: MailParser.addresses(payload.header("From")).first?.email) { sample.dmarcPass += 1 }
            }
            if payload.header("List-Unsubscribe") != nil {
                sample.withListUnsubscribe += 1
                if payload.header("List-Unsubscribe-Post") != nil { sample.withOneClickUnsubscribe += 1 }
            }
        }
        htmlSizes.sort()
        sample.htmlBytesMedian = htmlSizes.isEmpty ? 0 : htmlSizes[htmlSizes.count / 2]
        sample.htmlBytesMax = htmlSizes.last ?? 0
        return sample
    }

    /// The character set a part declares, in lowercase; `utf-8` when it says nothing.
    static func charset(of part: GmailAPI.Part) -> String {
        guard let type = part.header("Content-Type")?.lowercased(), let range = type.range(of: "charset=") else { return "utf-8" }
        let value = type[range.upperBound...].prefix { $0 != ";" && !$0.isWhitespace }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// The bytes read in the declared character set; `nil` when they do not fit it.
    static func text(_ bytes: Data, charset: String) -> String? {
        let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard encoding != kCFStringEncodingInvalidId else { return nil }
        return String(data: bytes, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
    }
}

/// The one write step 0 makes, on a test mail Paul sent himself: is the trash reached on the seen messages only,
/// and does undoing bring the mail back to the inbox?
public struct MailTrashEssay: Codable, Sendable, Equatable {
    public static let subject = "Polhub essai"

    public var found = false
    public var trashed = false
    public var leftInbox = false
    public var restored = false
    public var error: String?

    public init() {}

    public var text: String {
        guard found else { return "Aucun mail d'essai trouvé : envoie-toi un mail dont l'objet est « \(Self.subject) », puis relance." }
        if let error { return "Essai interrompu : \(error)." }
        return "Corbeille : \(trashed ? "oui" : "non") · sorti de la boîte de réception : \(leftInbox ? "oui" : "non") · revenu après annulation : \(restored ? "oui" : "non")"
    }

    /// Never from the development build: it only reads real mailboxes.
    public static func run(send: MailProbe.Send, flavor: AppFlavor = .current) async -> MailTrashEssay {
        var essay = MailTrashEssay()
        guard flavor == .prod else {
            essay.error = "\(GoogleError.readOnlyBuild)"
            return essay
        }
        func labels(_ id: String) async throws -> [String] {
            let data = try await send { GmailAPI.messageRequest(accessToken: $0, id: id, format: .minimal) }
            return try GmailAPI.decode(GmailAPI.Message.self, from: data).labelIds ?? []
        }
        do {
            let page = try GmailAPI.decode(GmailAPI.IDPage.self, from: try await send {
                GmailAPI.messagesRequest(accessToken: $0, query: "in:inbox subject:\"\(subject)\" newer_than:2d", maxResults: 1)
            })
            guard let id = page.ids.first else { return essay }
            essay.found = true
            _ = try await send { GmailAPI.batchModifyRequest(accessToken: $0, ids: [id], add: ["TRASH"], remove: ["INBOX"]) }
            let after = try await labels(id)
            essay.trashed = after.contains("TRASH")
            essay.leftInbox = !after.contains("INBOX")
            _ = try await send { GmailAPI.untrashRequest(accessToken: $0, id: id) }
            var back = try await labels(id)
            if !back.contains("INBOX") && !back.contains("TRASH") {
                // Out of the trash but archived: undoing must put the inbox label back itself.
                _ = try await send { GmailAPI.batchModifyRequest(accessToken: $0, ids: [id], add: ["INBOX"], remove: []) }
                back = try await labels(id)
            }
            essay.restored = back.contains("INBOX") && !back.contains("TRASH")
        } catch {
            essay.error = MailProbe.code(error)
        }
        return essay
    }
}

/// The address that opens a thread in Gmail's own page, under the right account.
public enum GmailLink {
    /// `folder`: Gmail's own, `all`, `trash` or `spam`.
    public static func thread(_ threadID: String, account: String, folder: String = "all") -> URL {
        var components = URLComponents(string: "https://mail.google.com/mail/")!
        components.queryItems = [URLQueryItem(name: "authuser", value: account)]
        components.fragment = "\(folder)/\(threadID)"
        return components.url!
    }
}
