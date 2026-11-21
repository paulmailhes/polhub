import Foundation
import HubDesign
import VigieKit

/// What Vigie notifies, taken from the app Vigie (21/11, the migration: Paul turns the app off, hub notifies in its
/// place). After each reading of the engine: what is new is notified once — remembered from one launch to the next —,
/// three banners at most, the most important first; what asks nothing goes to the notification center without a banner;
/// a wait that ended takes its notification away; a request that finishes again replaces its notification in place.
/// Pure: the app delivers what it decides.
public enum VigieNotifications {
    /// The kinds, each one a setting (Réglages › Vigie › Notifications), as the app Vigie's.
    public enum Kind: String, CaseIterable, Codable, Sendable {
        case waiting, sensitive, failed, question, accountSession, accountWeek, missionDone, stopped, runaway

        public var title: String {
            switch self {
            case .waiting: "Une conversation t'attend ou te pose une question"
            case .sensitive: "Une action sensible attend ton accord"
            case .failed: "Une action autorisée a échoué"
            case .question: "Vigie a répondu à une question à ta place"
            case .accountSession: "Un compte passe 90 % de sa session pendant qu'une conversation tourne"
            case .accountWeek: "Un compte passe 80 % puis 90 % de sa semaine, ou sera plein avant la remise à zéro"
            case .missionDone: "Une conversation ou un workflow a fini"
            case .stopped: "Une conversation s'arrête avant la fin"
            case .runaway: "Une conversation s'emballe"
            }
        }

        /// The order of importance when several leave together: the first three make a banner.
        public var priority: Int {
            switch self {
            case .sensitive: 0
            case .waiting: 1
            case .stopped: 2
            case .accountSession: 3
            case .failed: 4
            case .missionDone: 5
            case .runaway: 6
            case .question: 7
            case .accountWeek: 8
            }
        }
    }

    public struct Notice: Equatable, Sendable {
        /// Once per key: the same element is never notified twice.
        public var key: String
        public var kind: Kind
        public var title: String
        public var subtitle: String
        public var body: String
        /// The conversation a click opens.
        public var conversationID: String?
        /// Asks nothing: the notification center, without a banner or a sound.
        public var quiet: Bool
        /// A newer version of the same element replaces its notification in place.
        public var version: Double

        public init(key: String, kind: Kind, title: String, subtitle: String = "", body: String, conversationID: String? = nil,
                    quiet: Bool = false, version: Double = 0) {
            self.key = key
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.conversationID = conversationID
            self.quiet = quiet
            self.version = version
        }
    }

    /// What was notified, kept from one launch to the next.
    public struct State: Codable, Equatable, Sendable {
        /// The first reading marks everything seen: no burst at the first launch.
        public var seeded = false
        public var seen: [String: Double] = [:]
        public var versions: [String: Double] = [:]
        /// The waits notified and still waiting: their notification goes when they end.
        public var live: Set<String> = []
        /// The ends notified per conversation: they go when it works again.
        public var ends: [String: [String]] = [:]

        public init() {}
    }

    public struct Outcome: Equatable, Sendable {
        /// What to notify, in order; `banner` says which make a banner.
        public var post: [Notice] = []
        public var banners: Set<String> = []
        /// The notifications to take away.
        public var remove: [String] = []
    }

    public static let maxBanners = 3
    /// A conversation that waits in VS Code is notified after twenty seconds (the engine's own rule, kept for an older one).
    public static let waitConfirm: TimeInterval = 20
    /// A limit is said while it is fresh.
    public static let limitFresh: TimeInterval = 15 * 60
    /// A workflow's end waits two minutes: the conversation often goes on.
    public static let workflowGrace: TimeInterval = 2 * 60
    /// « S'emballe », once per conversation and per three hours.
    public static let runawaySlot: TimeInterval = 3 * 3_600

    /// What to notify after a reading. `silent`: the app Vigie runs and notifies itself — everything is marked seen,
    /// nothing is posted, so that nothing bursts out when it stops. `inFront`: the page of this conversation is in front
    /// of Paul — no banner.
    public static func plan(_ overview: VigieOverview, state: inout State, now: Date, enabled: (Kind) -> Bool = { _ in true },
                            inFront: (String?) -> Bool = { _ in false }, silent: Bool = false) -> Outcome {
        let candidates = collect(overview, now: now)
        let time = now.timeIntervalSince1970
        var outcome = Outcome()
        guard state.seeded, !silent else {
            for candidate in candidates {
                state.seen[candidate.key] = state.seen[candidate.key] ?? time
                state.versions[candidate.key] = candidate.version
            }
            state.seeded = true
            state.live = Set(candidates.filter { $0.kind == .waiting || $0.kind == .sensitive }.map(\.key))
            forget(&state, time: time)
            return outcome
        }
        // A conversation that works again: its end announced is no longer true.
        for conversation in overview.conversations where conversation.status == .working {
            if let keys = state.ends.removeValue(forKey: conversation.id) { outcome.remove += keys }
        }
        let fresh = candidates.filter { state.seen[$0.key] == nil }
        let updated = candidates.filter { candidate in
            guard state.seen[candidate.key] != nil, let known = state.versions[candidate.key] else { return false }
            return candidate.version > known
        }
        for candidate in fresh + updated {
            state.seen[candidate.key] = state.seen[candidate.key] ?? time
            state.versions[candidate.key] = candidate.version
            if candidate.kind == .missionDone, let conversation = candidate.conversationID {
                state.ends[conversation, default: []].append(candidate.key)
            }
        }
        let shown = fresh.filter { enabled($0.kind) }.sorted { $0.kind.priority < $1.kind.priority }
        for candidate in shown {
            if outcome.banners.count < maxBanners, !candidate.quiet, !inFront(candidate.conversationID) { outcome.banners.insert(candidate.key) }
            outcome.post.append(candidate)
        }
        outcome.post += updated.filter { enabled($0.kind) }
        // The waits that ended (allowed, answered, refused when the time ran out): their notification goes.
        let live = Set(candidates.filter { $0.kind == .waiting || $0.kind == .sensitive }.map(\.key))
        outcome.remove += state.live.subtracting(live).sorted()
        state.live = live
        forget(&state, time: time)
        return outcome
    }

    /// An element is remembered four days, a week's alert eight.
    static func forget(_ state: inout State, time: Double) {
        state.seen = state.seen.filter { time - $0.value < ($0.key.hasPrefix("a:") ? 8 : 4) * 86_400 }
        state.versions = state.versions.filter { state.seen[$0.key] != nil }
    }

    /// What deserves a notification now: a banner for what asks a gesture or went wrong; the center only for what asks
    /// nothing (a question answered for Paul, a workflow that succeeded, a conversation started on another account).
    public static func collect(_ overview: VigieOverview, now: Date) -> [Notice] {
        var list: [Notice] = []
        let name = { (id: String?, fallback: String?) in overview.conversationName(id, fallback: fallback) }
        for item in overview.toReview {
            let conversation = name(item.conversationID, item.conversationTitle)
            if item.isPendingDecision {
                // What it is and what happens without an answer; never the raw command (it is in the page).
                list.append(Notice(key: "r:" + item.id, kind: .sensitive, title: "À autoriser · \(conversation)",
                                   subtitle: nonEmpty(item.title) ?? item.rule ?? "Action sensible", body: sensitiveBody(item),
                                   conversationID: item.conversationID))
            } else if item.kind == .blocked, item.reason == "echec" {
                list.append(Notice(key: "r:" + item.id, kind: .failed, title: "Action autorisée en échec · \(conversation)",
                                   body: nonEmpty(item.detail) ?? item.rule ?? "L'action autorisée a échoué", conversationID: item.conversationID))
            } else if item.kind == .question {
                var body = "« \(nonEmpty(item.title) ?? "Question") »"
                if let chosen = item.question?.items.compactMap(\.chosenText).first { body += " : \(chosen)" }
                list.append(Notice(key: "r:" + item.id, kind: .question, title: "Réponse choisie pour toi · \(conversation)", body: body,
                                   conversationID: item.conversationID, quiet: true))
            } else if item.kind == .limit {
                guard let at = item.at, now.timeIntervalSince(at) < limitFresh else { continue }
                list.append(Notice(key: "r:" + item.id, kind: .stopped, title: "\(conversation) s'est arrêtée, pas finie",
                                   subtitle: nonEmpty(item.title) ?? "Limite atteinte", body: nonEmpty(item.detail) ?? "Limite atteinte",
                                   conversationID: item.conversationID))
            } else if item.id.hasPrefix("w:") {
                list.append(Notice(key: "r:" + item.id, kind: .waiting,
                                   title: item.isPlan ? "\(conversation) te propose un plan" : "\(conversation) te pose une question",
                                   subtitle: item.detail ?? "", body: nonEmpty(item.title) ?? "Elle attend ta réponse",
                                   conversationID: item.conversationID))
            } else if item.id.hasPrefix("c:") {
                // Waiting for less than twenty seconds: not yet, and not marked seen.
                guard let since = item.at, now.timeIntervalSince(since) >= waitConfirm else { continue }
                let permission = item.title.contains("accord")
                list.append(Notice(key: "r:\(item.id):\(Int(since.timeIntervalSince1970))", kind: .waiting,
                                   title: "\(conversation) attend \(permission ? "ton accord" : "ta réponse")",
                                   body: "En attente depuis \(clock(since)).", conversationID: item.conversationID))
            } else if item.kind == .notice || item.kind == .waiting {
                // An account to connect again, an account switched, a conversation started on another account.
                list.append(Notice(key: "r:" + item.id, kind: .waiting, title: nonEmpty(item.title) ?? "Vigie",
                                   subtitle: item.conversationID != nil ? conversation : "", body: item.detail ?? "",
                                   conversationID: item.conversationID, quiet: item.id.hasPrefix("cf:")))
            }
        }
        list += accounts(overview, now: now)
        list += ends(overview, now: now)
        for conversation in overview.conversations where conversation.status != .closed {
            guard let alert = conversation.alert, alert.kind == "emballe" else { continue }
            let slot = Int((alert.since ?? now).timeIntervalSince1970 / runawaySlot)
            list.append(Notice(key: "e:\(conversation.id):\(slot)", kind: .runaway, title: "\(name(conversation.id, nil)) s'emballe",
                               body: nonEmpty(alert.reason) ?? "Consommation anormale", conversationID: conversation.id))
        }
        return list
    }

    /// A week at 80 % then 90 %, or full before it starts again; a session at 90 % while a conversation works on it.
    static func accounts(_ overview: VigieOverview, now: Date) -> [Notice] {
        var list: [Notice] = []
        for account in overview.accounts {
            if let week = account.week {
                let reset = week.resetsAt.map { Int($0.timeIntervalSince1970) } ?? 0
                if let top = [90, 80].first(where: { week.percent >= Double($0) }) {
                    var body = "\(Int(week.percent.rounded())) % de la semaine utilisés"
                    if let resetsAt = week.resetsAt { body += " · remise à zéro \(day(resetsAt, now: now))" }
                    list.append(Notice(key: "a:\(account.id):semaine:\(top):\(reset)", kind: .accountWeek,
                                       title: "\(account.label) passe \(top) % de sa semaine", body: body))
                } else if let full = week.fullAt, let resetsAt = week.resetsAt, full < resetsAt, full > now {
                    list.append(Notice(key: "a:\(account.id):plein:\(reset)", kind: .accountWeek,
                                       title: "\(account.label) sera plein avant la remise à zéro",
                                       body: "Plein vers \(day(full, now: now)), remise à zéro \(day(resetsAt, now: now))"))
                }
            }
            if let session = account.session, session.percent >= 90 {
                let working = overview.conversations.filter { $0.status == .working && $0.accountID == account.id }
                guard !working.isEmpty else { continue }
                let reset = session.resetsAt.map { Int($0.timeIntervalSince1970) } ?? 0
                var body = (working.count == 1 ? "\(working[0].title) va bientôt s'arrêter" : "\(working.count) conversations vont bientôt s'arrêter")
                if let resetsAt = session.resetsAt { body += " · remise à zéro à \(clock(resetsAt))" }
                list.append(Notice(key: "a:\(account.id):session:\(reset)", kind: .accountSession,
                                   title: "\(account.label) à \(Int(session.percent.rounded())) % de sa session", body: body))
            }
        }
        return list
    }

    /// A request that finished (« a fini · durée », « À toi »), a workflow that finished after its grace.
    static func ends(_ overview: VigieOverview, now: Date) -> [Notice] {
        var list: [Notice] = []
        for report in overview.reports {
            let conversation = overview.conversationName(report.conversationID, fallback: report.conversationTitle)
            let version = report.at?.timeIntervalSince1970 ?? 0
            switch report.kind {
            case "missionDone":
                // The engine's id already says « fin:<conversation>:<request> ».
                let key = report.id ?? "fin:\(report.conversationID ?? ""):\(version)"
                if let question = nonEmpty(report.question) {
                    list.append(Notice(key: key, kind: .waiting, title: "\(conversation) te pose une question", subtitle: report.prompt ?? "",
                                       body: question, conversationID: report.conversationID, version: version))
                    continue
                }
                let duration = report.duration.map { Words.duration(Int($0)) } ?? ""
                var lines = [nonEmpty(report.title)].compactMap { $0 }
                if let toYou = nonEmpty(report.toYou) { lines.append("À toi : \(toYou)") }
                list.append(Notice(key: key, kind: .missionDone, title: duration.isEmpty ? "\(conversation) a fini" : "\(conversation) a fini · \(duration)",
                                   subtitle: report.prompt ?? "", body: lines.isEmpty ? "Fini" : lines.joined(separator: "\n"),
                                   conversationID: report.conversationID, version: version))
            case "workflowDone":
                guard let at = report.at, now.timeIntervalSince(at) >= workflowGrace else { continue }
                let outcome = switch report.status {
                case "failed": "en échec"
                case "killed": "arrêté"
                default: (report.agentsFailed ?? 0) > 0 ? "fini, \(report.agentsFailed ?? 0) agent en échec" : "fini"
                }
                list.append(Notice(key: report.id ?? "wf:\(report.conversationID ?? ""):\(version)", kind: .missionDone,
                                   title: "\(conversation) · workflow \(outcome)", subtitle: report.title ?? "",
                                   body: nonEmpty(report.detail) ?? "Workflow \(outcome)", conversationID: report.conversationID,
                                   quiet: report.status == "done" && (report.agentsFailed ?? 0) == 0, version: version))
            default:
                continue
            }
        }
        return list
    }

    static func sensitiveBody(_ item: VigieReview) -> String {
        guard let expires = item.expiresAt else { return "Clique pour décider." }
        return "Refusée à \(clock(expires)) sans réponse. Clique pour décider."
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }

    /// « 14:05 », in the Mac's hour.
    static func clock(_ date: Date) -> String {
        Words.time(date)
    }

    /// « demain à 20:00 », « lundi 30 à 20:00 ».
    static func day(_ date: Date, now: Date) -> String {
        Words.day(date, now: now) + " à " + Words.time(date)
    }
}
