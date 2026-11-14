import Domain
import Foundation
import Persistence

/// A meeting's summary: what was said, what was decided, what is to be done (design of 12/11).
public struct MeetingSummary: Codable, Equatable, Sendable {
    public var overview: String
    public var decisions: [String]
    public var actions: [SummaryAction]

    public init(overview: String, decisions: [String], actions: [SummaryAction]) {
        self.overview = overview
        self.decisions = decisions
        self.actions = actions
    }
}

public struct SummaryAction: Codable, Equatable, Sendable {
    public var text: String
    /// « Moi », a name said in the meeting, « Interlocuteur », or nobody.
    public var owner: String?
    /// As said: « vendredi », « dans deux semaines ».
    public var due: String?

    public init(text: String, owner: String? = nil, due: String? = nil) {
        self.text = text
        self.owner = owner
        self.due = due
    }
}

public enum SummaryError: Error, CustomStringConvertible {
    case model(String)
    case unavailable(String)

    public var description: String {
        switch self {
        case .model(let text), .unavailable(let text): text
        }
    }
}

/// The model that writes: Apple's in the app, a stand-in in the tests.
public protocol SummaryEngine: Sendable {
    /// Why it cannot run now, or `nil` when it can.
    var unavailableReason: String? { get }
    /// The notes of one part of the transcript.
    func notes(for chunk: String, part: Int, of count: Int) async throws -> String
    /// The summary, from the notes of every part.
    func summary(of notes: [String], title: String) async throws -> MeetingSummary
}

/// The transcript as the model reads it, in parts that fit its window.
public enum SummaryPlan {
    /// Apple's model reads 8 192 tokens: about 10 000 characters of French leave room for the instructions
    /// and the answer (measured on 14/11).
    public static let maxCharacters = 10_000

    /// « [01:05] Moi : … »; an imported paragraph as it is.
    public static func lines(_ utterances: [UtteranceRow]) -> [String] {
        utterances.map { line in
            guard line.speaker != .unknown else { return line.text }
            let seconds = line.startMs / 1_000
            return String(format: "[%02d:%02d] ", seconds / 60, seconds % 60) + line.speaker.label + " : " + line.text
        }
    }

    /// Parts cut between lines; a line longer than a part is cut on its own.
    public static func chunks(_ lines: [String], maxCharacters: Int = maxCharacters) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in lines {
            var rest = Substring(line + "\n")
            while !rest.isEmpty {
                if current.count + rest.count <= maxCharacters {
                    current += rest
                    rest = ""
                } else if current.isEmpty {
                    current = String(rest.prefix(maxCharacters))
                    rest = rest.dropFirst(maxCharacters)
                    chunks.append(current)
                    current = ""
                } else {
                    chunks.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

/// What the code checks after the model (design of 12/11: no invented name).
public enum SummaryChecks {
    public static let maxDecisions = 8
    public static let maxActions = 10
    static let nobody: Set<String> = ["", "les autres", "l'equipe", "equipe", "l’equipe", "tous", "nous", "on", "personne", "?", "inconnu", "non specifie"]
    static let vagueDue = ["non ", "non-", "determin", "precis", "specifi", "inconnu", "aucun", "pas de", "?", "n/a", "immediat"]

    public static func clean(_ summary: MeetingSummary, transcript: String, participants: [String]) -> MeetingSummary {
        let words = Set(tokens(transcript + " " + participants.joined(separator: " ")))
        var actions: [SummaryAction] = []
        var seen = Set<String>()
        for action in summary.actions {
            let text = capitalized(action.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty, seen.insert(fold(text)).inserted else { continue }
            actions.append(SummaryAction(text: text, owner: owner(action.owner, known: words), due: due(action.due)))
        }
        var decisions: [String] = []
        var seenDecisions = Set<String>()
        for decision in summary.decisions {
            let text = decision.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = fold(text).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            guard !text.isEmpty, seenDecisions.insert(key).inserted else { continue }
            decisions.append(capitalized(text))
        }
        return MeetingSummary(overview: summary.overview.trimmingCharacters(in: .whitespacesAndNewlines),
                              decisions: Array(decisions.prefix(maxDecisions)), actions: Array(actions.prefix(maxActions)))
    }

    static func owner(_ raw: String?, known: Set<String>) -> String? {
        let name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = fold(name)
        if nobody.contains(folded) { return nil }
        if ["moi", "je", "utilisateur", "l'utilisateur"].contains(folded) { return "Moi" }
        let parts = tokens(name).filter { $0.count >= 3 }
        return !parts.isEmpty && parts.allSatisfy(known.contains) ? name : "Interlocuteur"
    }

    static func due(_ raw: String?) -> String? {
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = fold(text) + " "
        guard !text.isEmpty, !vagueDue.contains(where: folded.contains) else { return nil }
        return text
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    static func tokens(_ text: String) -> [String] {
        fold(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// What the base keeps: the text on the meeting, the actions as rows.
public enum SummaryText {
    public static func markdown(_ summary: MeetingSummary) -> String {
        var text = "## Résumé\n\n" + summary.overview
        if !summary.decisions.isEmpty {
            text += "\n\n## Décisions\n\n" + summary.decisions.map { "- " + $0 }.joined(separator: "\n")
        }
        return text
    }

    public static func actionRows(_ actions: [SummaryAction], at date: Date) -> [ActionRow] {
        actions.enumerated().map { index, action in
            ActionRow(text: action.text + (action.due.map { " (\($0))" } ?? ""), owner: action.owner, position: Double(index), createdAt: date)
        }
    }
}

/// From the transcript to the checked summary: notes part by part, then one summary.
public enum Summarizer {
    /// Under this, there is nothing to summarize.
    public static let minimumCharacters = 300

    public static func make(lines: [UtteranceRow], title: String, participants: [String], engine: any SummaryEngine) async throws -> MeetingSummary? {
        let text = SummaryPlan.lines(lines)
        let transcript = text.joined(separator: "\n")
        guard transcript.count >= minimumCharacters else { return nil }
        let chunks = SummaryPlan.chunks(text)
        var notes: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            notes.append(try await engine.notes(for: chunk, part: index + 1, of: chunks.count))
        }
        try Task.checkCancellation()
        let summary = try await engine.summary(of: notes, title: title)
        try Task.checkCancellation()
        return SummaryChecks.clean(summary, transcript: transcript, participants: participants)
    }
}
