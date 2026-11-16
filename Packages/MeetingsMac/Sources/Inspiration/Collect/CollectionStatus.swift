import Foundation
import Persistence

/// The two automatic collections.
public enum CollectionJob: String, Sendable, CaseIterable, Codable {
    /// Awwwards' site of the day.
    case websites
    /// The posts of the LinkedIn pages followed.
    case branding
}

/// How the last reading of one source went (Awwwards, or one LinkedIn page), in plain words for Réglages ›
/// Inspiration: « Lu à 14:02, 2 nouveaux posts », « LinkedIn demande une connexion : réessai au prochain tour ».
public struct CollectionStatus: Sendable, Equatable, Identifiable {
    public enum Source: Hashable, Sendable {
        case awwwards
        /// An `inspiration_source`, by its id.
        case linkedIn(UUID)
    }

    public enum Outcome: Sendable, Equatable {
        /// Read; `newItems` added (`nil` when not known: a reading restored from the base).
        case read(newItems: Int?)
        /// LinkedIn asked for a login.
        case loginWall
        /// LinkedIn's 999: it refuses visitors for a while.
        case refused
        /// HTTP 429: too many requests.
        case slowDown
        /// HTTP 404: the page is gone, or its link is wrong.
        case notFound
        /// A page without any post (LinkedIn changed its page?).
        case noPosts
        /// No Internet connection.
        case offline
        /// Anything else, already in plain words.
        case failed(String)
    }

    public var source: Source
    /// « Awwwards », or the LinkedIn page's name.
    public var name: String
    /// When it was read.
    public var date: Date
    public var outcome: Outcome

    public var id: Source { source }

    public init(source: Source, name: String, date: Date, outcome: Outcome) {
        self.source = source
        self.name = name
        self.date = date
        self.outcome = outcome
    }

    /// The last reading of a LinkedIn page, as the base keeps it (`lastReadAt`, `lastError`); `nil` when it was
    /// never read.
    public init?(page: InspirationSourceRow) {
        guard let date = page.lastReadAt else { return nil }
        self.init(source: .linkedIn(page.id), name: page.name, date: date,
                  outcome: page.lastError.map { .failed($0) } ?? .read(newItems: nil))
    }

    /// Something went wrong: the line is said as a problem.
    public var isProblem: Bool {
        if case .read = outcome { return false }
        return true
    }

    /// The problem in plain words, as `inspiration_source.lastError` keeps it; `nil` when it went well.
    public var problem: String? {
        switch outcome {
        case .read: nil
        case .loginWall: "LinkedIn demande une connexion : réessai au prochain tour"
        case .refused: "LinkedIn refuse la lecture pour l'instant : réessai au prochain tour"
        case .slowDown: "LinkedIn demande de ralentir : réessai au prochain tour"
        case .notFound: "Page introuvable : vérifie son lien"
        case .noPosts: "Aucun post visible sur la page : réessai au prochain tour"
        case .offline: "Pas de connexion à Internet : réessai au prochain tour"
        case .failed(let reason): reason
        }
    }

    /// The line Réglages shows: « Lu à 14:02, 2 nouveaux posts », « Lu hier à 20:00 », or the problem.
    public func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        if let problem { return problem }
        let when = Self.when(date, now: now, calendar: calendar)
        guard case .read(let count?) = outcome else { return "Lu \(when)" }
        let noun = source == .awwwards ? "site" : "post"
        switch count {
        case 0: return source == .awwwards ? "Lu \(when), rien de nouveau" : "Lu \(when), aucun nouveau post"
        case 1: return "Lu \(when), 1 nouveau \(noun)"
        default: return "Lu \(when), \(count) nouveaux \(noun)s"
        }
    }

    /// « à 14:02 », « hier à 20:00 », « le 12/11 à 09:00 ».
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "à \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "hier à \(time)"
        }
        formatter.dateFormat = "dd/MM"
        return "le \(formatter.string(from: date)) à \(time)"
    }
}

/// What one collection did.
public struct CollectionRun: Sendable, Equatable {
    public var job: CollectionJob
    /// The items added, newest last: what the tagger reads next.
    public var added: [InspirationItemRow]
    /// Items seen again and completed (the same project from a second page).
    public var updated: Int
    /// One line per source read.
    public var statuses: [CollectionStatus]
    /// Another collection of the same kind was under way: nothing was done.
    public var skipped: Bool

    public init(job: CollectionJob, added: [InspirationItemRow] = [], updated: Int = 0, statuses: [CollectionStatus] = [], skipped: Bool = false) {
        self.job = job
        self.added = added
        self.updated = updated
        self.statuses = statuses
        self.skipped = skipped
    }

    /// The run did not happen for want of a connection: it does not count as a run (the next check tries again).
    public var wasOffline: Bool {
        !statuses.isEmpty && statuses.allSatisfy { $0.outcome == .offline }
    }
}
