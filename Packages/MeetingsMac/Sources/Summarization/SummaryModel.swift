import Domain
import Foundation
import Persistence

/// A meeting's summary: what was said, what matters, what was decided, what is to be done (design of 12/11,
/// « Points clés » 15/11).
public struct MeetingSummary: Codable, Equatable, Sendable {
    public var overview: String
    /// « Points clés »: what matters, one sentence each, without the decisions again.
    public var points: [String]
    public var decisions: [String]
    public var actions: [SummaryAction]
    /// What could not be summarized (« Partiel », 15/11), as a phrase for Paul; `nil` when nothing is missing.
    public var missing: String?

    public init(overview: String, points: [String] = [], decisions: [String], actions: [SummaryAction], missing: String? = nil) {
        self.overview = overview
        self.points = points
        self.decisions = decisions
        self.actions = actions
        self.missing = missing
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(String.self, forKey: .overview)
        points = try container.decodeIfPresent([String].self, forKey: .points) ?? []
        decisions = try container.decode([String].self, forKey: .decisions)
        actions = try container.decode([SummaryAction].self, forKey: .actions)
        missing = try container.decodeIfPresent(String.self, forKey: .missing)
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

public enum SummaryError: Error, Equatable, CustomStringConvertible {
    case model(String)
    /// Not now: the model is missing or busy; it starts again a minute later, without counting as a failure.
    case unavailable(String)
    /// The text does not fit the model's window.
    case tooLong
    /// The model refused the passage (its guardrails).
    case refused

    public var description: String {
        switch self {
        case .model(let text), .unavailable(let text): text
        case .tooLong: "La transcription dépasse la fenêtre du modèle."
        case .refused: "Le modèle d'Apple a refusé ce passage."
        }
    }
}

/// Where a summary is, part by part (15/11): kept in memory, the page shows it while it is written.
public struct SummaryProgress: Equatable, Sendable {
    /// The parts of the transcript whose notes are taken.
    public var done: Int
    public var total: Int
    /// Every part is read: the summary itself is being written.
    public var finishing: Bool

    public init(done: Int, total: Int, finishing: Bool = false) {
        self.done = done
        self.total = total
        self.finishing = finishing
    }

    /// The parts, then the summary as one more step.
    public var fraction: Double {
        total <= 0 ? 0 : min(1, Double(done) / Double(total + 1))
    }
}

/// The model that writes: Apple's in the app, a stand-in in the tests.
public protocol SummaryEngine: Sendable {
    /// Why it cannot run now, or `nil` when it can.
    var unavailableReason: String? { get }
    /// How many characters of transcript one request takes, beside its instructions and its answer.
    func characterBudget() async -> Int
    /// The notes of one part of the transcript.
    func notes(for chunk: String, part: Int, of count: Int) async throws -> String
    /// Notes of several parts merged into shorter ones: the extra rounds of a long meeting.
    func merge(_ notes: String, part: Int, of count: Int) async throws -> String
    /// The summary, from the notes of every part.
    func summary(of notes: [String], title: String) async throws -> MeetingSummary
}

extension SummaryEngine {
    public func characterBudget() async -> Int { SummaryPlan.maxCharacters }

    public func merge(_ notes: String, part: Int, of count: Int) async throws -> String {
        try await self.notes(for: notes, part: part, of: count)
    }
}

/// The transcript as the model reads it, in parts that fit its window.
public enum SummaryPlan {
    /// The largest part: about 10 000 characters of French fit Apple's 8 192 tokens with the instructions and the
    /// answer (measured on 14/11). A part is never larger, even if the model says its window is.
    public static let maxCharacters = 10_000
    /// The smallest part, whatever the window says.
    public static let minimumCharacters = 2_000
    /// Tokens kept for the model's answer: the notes, or the summary (15/11, not measured).
    static let answerTokens = 1_200
    /// Tokens of the line that heads a part (« Extrait 2 sur 5 de la transcription : »).
    static let headTokens = 40

    /// « [01:05] Moi : … »; an imported paragraph as it is.
    public static func lines(_ utterances: [UtteranceRow]) -> [String] {
        utterances.map { line in
            guard line.speaker != .unknown else { return line.text }
            let seconds = line.startMs / 1_000
            return String(format: "[%02d:%02d] ", seconds / 60, seconds % 60) + line.speaker.label + " : " + line.text
        }
    }

    /// The characters a part can hold in the model's window: the window, less the instructions, the schema, the
    /// head and the answer, turned into characters with the ratio of a sample, with a tenth of margin.
    public static func characterBudget(contextSize: Int, fixedTokens: Int, sampleCharacters: Int, sampleTokens: Int) -> Int {
        let tokens = contextSize - fixedTokens - answerTokens - headTokens
        let perToken = Double(sampleCharacters) / Double(max(1, sampleTokens))
        let characters = Int(Double(max(0, tokens)) * perToken * 0.9)
        return min(maxCharacters, max(minimumCharacters, characters))
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

    /// A part cut in two, between two lines near the middle; a single line is cut at a space near its middle.
    public static func halves(_ chunk: String) -> (String, String) {
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if lines.count > 1 {
            var count = 0
            var index = 0
            while index < lines.count - 1, count + lines[index].count + 1 <= chunk.count / 2 {
                count += lines[index].count + 1
                index += 1
            }
            let cut = max(1, index)
            return (lines[..<cut].joined(separator: "\n") + "\n", lines[cut...].joined(separator: "\n") + "\n")
        }
        let middle = chunk.index(chunk.startIndex, offsetBy: chunk.count / 2)
        let cut = chunk[middle...].firstIndex(of: " ") ?? middle
        return (String(chunk[..<cut]), String(chunk[cut...]).trimmingCharacters(in: .whitespaces))
    }
}

/// The notes of a part, as the model's answers are written down for the next request.
public enum SummaryNotes {
    public static func text(part: Int, points: [String], decisions: [String], actions: [String]) -> String {
        var text = "Partie \(part)\nPoints :\n" + points.map { "- \($0)" }.joined(separator: "\n")
        text += "\nDécisions :\n" + decisions.map { "- \($0)" }.joined(separator: "\n")
        text += "\nActions :\n" + actions.map { "- \($0)" }.joined(separator: "\n")
        return text
    }

    /// The same notes without their points: the decisions and the actions matter most to the summary.
    static func withoutPoints(_ note: String) -> String {
        var inPoints = false
        return note.components(separatedBy: "\n").filter { line in
            if line == "Points :" { inPoints = true; return true }
            if line == "Décisions :" || line == "Actions :" { inPoints = false }
            return !(inPoints && line.hasPrefix("- "))
        }.joined(separator: "\n")
    }

    /// Notes that fit the budget: the points go first, from the last part up, every decision and action stays;
    /// only then is the end cut. `shortened` says something was left out (« Partiel »).
    static func fit(_ notes: [String], budget: Int) -> (notes: [String], shortened: Bool) {
        func length(_ notes: [String]) -> Int { notes.joined(separator: "\n\n").count }
        guard length(notes) > budget else { return (notes, false) }
        var notes = notes
        for index in notes.indices.reversed() where length(notes) > budget {
            notes[index] = withoutPoints(notes[index])
        }
        if length(notes) > budget { notes = [String(notes.joined(separator: "\n\n").prefix(budget))] }
        return (notes, true)
    }
}

/// What the code checks after the model (design of 12/11: no invented name).
public enum SummaryChecks {
    public static let maxPoints = 6
    public static let maxDecisions = 8
    public static let maxActions = 10
    static let nobody: Set<String> = ["", "les autres", "l'equipe", "equipe", "l’equipe", "tous", "nous", "on", "personne", "?", "inconnu", "non specifie"]
    static let vagueDue = ["non ", "non-", "determin", "precis", "specifi", "inconnu", "aucun", "pas de", "?", "n/a", "immediat",
                           "vide", "a venir", "bientot", "prochainement", "plus tard", "pas longtemps"]

    public static func clean(_ summary: MeetingSummary, transcript: String, participants: [String]) -> MeetingSummary {
        let words = Set(tokens(transcript + " " + participants.joined(separator: " ")))
        var actions: [SummaryAction] = []
        var seen = Set<String>()
        for action in summary.actions {
            let text = capitalized(action.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty, seen.insert(fold(text)).inserted else { continue }
            // A date the action already says is not repeated after it.
            let when = due(action.due).flatMap { fold(text).contains(fold($0)) ? nil : $0 }
            actions.append(SummaryAction(text: text, owner: owner(action.owner, known: words), due: when))
        }
        let decisions = unique(summary.decisions)
        // A key point that only repeats a decision goes (15/11).
        let points = unique(summary.points, besides: Set(decisions.map(key)))
        return MeetingSummary(overview: summary.overview.trimmingCharacters(in: .whitespacesAndNewlines),
                              points: Array(points.prefix(maxPoints)),
                              decisions: Array(decisions.prefix(maxDecisions)), actions: Array(actions.prefix(maxActions)),
                              missing: summary.missing)
    }

    /// Trimmed, capitalized, without the empty ones and the repeats.
    static func unique(_ lines: [String], besides taken: Set<String> = []) -> [String] {
        var seen = taken
        var result: [String] = []
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(key(text)).inserted else { continue }
            result.append(capitalized(text))
        }
        return result
    }

    static func key(_ text: String) -> String {
        fold(text).trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
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

/// From the transcript to the checked summary: notes part by part, then one summary. A part the model refuses,
/// or notes that had to be shortened, leave the summary « Partiel » instead of sinking it (15/11).
public enum Summarizer {
    /// Under this, there is nothing to summarize.
    public static let minimumCharacters = 300

    /// Notes longer than this go through another round of notes before the summary.
    static let reductionRounds = 3
    /// A part too long for the window is cut in two, this many times at most.
    static let splits = 4

    public static func make(lines: [UtteranceRow], title: String, participants: [String], engine: any SummaryEngine,
                            maxCharacters: Int? = nil,
                            shouldStop: @Sendable () async -> Bool = { false },
                            onProgress: @Sendable (SummaryProgress) async -> Void = { _ in }) async throws -> MeetingSummary? {
        let text = SummaryPlan.lines(lines)
        let transcript = text.joined(separator: "\n")
        guard transcript.count >= minimumCharacters else { return nil }
        func check() async throws {
            try Task.checkCancellation()
            if await shouldStop() { throw CancellationError() }
        }
        let budget: Int
        if let maxCharacters { budget = maxCharacters } else { budget = await engine.characterBudget() }
        let chunks = SummaryPlan.chunks(text, maxCharacters: budget)
        await onProgress(SummaryProgress(done: 0, total: chunks.count))
        var notes: [String] = []
        var dropped: [Int] = []
        for (index, chunk) in chunks.enumerated() {
            let part = try await self.notes(of: chunk, part: index + 1, of: chunks.count, engine: engine, check: check)
            notes += part.notes
            if part.lost { dropped.append(index + 1) }
            await onProgress(SummaryProgress(done: index + 1, total: chunks.count))
        }
        // Nothing the model would read: the meeting cannot be summarized.
        guard !notes.isEmpty else { throw SummaryError.refused }
        // A long meeting's notes do not fit the model's window: they are merged, in groups (review of 14/11,
        // Important 6), a few rounds at most.
        var round = 0
        while notes.joined(separator: "\n\n").count > budget, notes.count > 1, round < reductionRounds {
            let groups = SummaryPlan.chunks(notes, maxCharacters: budget)
            var merged: [String] = []
            for (index, group) in groups.enumerated() {
                try await check()
                do {
                    merged.append(try await merge(group, part: index + 1, of: groups.count, engine: engine))
                } catch SummaryError.refused, SummaryError.tooLong {
                    // A group the model will not merge keeps its notes as they are.
                    merged.append(group)
                }
            }
            notes = merged
            round += 1
        }
        var (fitted, shortened) = SummaryNotes.fit(notes, budget: budget)
        await onProgress(SummaryProgress(done: chunks.count, total: chunks.count, finishing: true))
        try await check()
        var summary: MeetingSummary
        do {
            summary = try await engine.summary(of: fitted, title: title)
        } catch SummaryError.tooLong {
            // The window was smaller than said: once more with half the notes.
            fitted = SummaryNotes.fit(fitted, budget: budget / 2).notes
            shortened = true
            try await check()
            summary = try await engine.summary(of: fitted, title: title)
        }
        try Task.checkCancellation()
        summary = SummaryChecks.clean(summary, transcript: transcript, participants: participants)
        summary.missing = SummaryText.missing(dropped: dropped, of: chunks.count, shortened: shortened)
        return summary
    }

    /// One part's notes. A part too long for the window is cut in two and each half is read; what the model
    /// refuses is left out (`lost`).
    static func notes(of chunk: String, part: Int, of count: Int, engine: any SummaryEngine, check: () async throws -> Void,
                      depth: Int = 0) async throws -> (notes: [String], lost: Bool) {
        try await check()
        do {
            return ([try await engine.notes(for: chunk, part: part, of: count)], false)
        } catch SummaryError.refused {
            return ([], true)
        } catch SummaryError.tooLong {
            guard depth < splits, chunk.count > 1 else { return ([], true) }
            let (first, second) = SummaryPlan.halves(chunk)
            let one = try await notes(of: first, part: part, of: count, engine: engine, check: check, depth: depth + 1)
            let two = try await notes(of: second, part: part, of: count, engine: engine, check: check, depth: depth + 1)
            return (one.notes + two.notes, one.lost || two.lost)
        }
    }

    /// One group of notes merged; too long for the window, it is cut in two.
    static func merge(_ group: String, part: Int, of count: Int, engine: any SummaryEngine, depth: Int = 0) async throws -> String {
        do {
            return try await engine.merge(group, part: part, of: count)
        } catch SummaryError.tooLong where depth < splits {
            let (first, second) = SummaryPlan.halves(group)
            return try await merge(first, part: part, of: count, engine: engine, depth: depth + 1) + "\n\n"
                + merge(second, part: part, of: count, engine: engine, depth: depth + 1)
        }
    }
}
