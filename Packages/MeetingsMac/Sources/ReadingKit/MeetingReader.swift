import Domain
import Foundation
import Persistence

/// A tool refused: the text says why, in French, for Claude Code or for Paul.
public struct ToolError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// The meetings as text, read-only: what `polhub` prints and what the MCP server answers.
public struct MeetingReader: Sendable {
    public static let pageSize = 200
    let meetings: MeetingStore
    let transcripts: TranscriptStore
    let now: @Sendable () -> Date
    let timeZone: TimeZone

    public init(meetings: MeetingStore, transcripts: TranscriptStore, now: @escaping @Sendable () -> Date = Date.init,
                timeZone: TimeZone = .current) {
        self.meetings = meetings
        self.transcripts = transcripts
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: - The three tools

    /// Newest first, numbered: the number is what `reunion` takes.
    public func list(since: Date?, limit: Int) throws -> String {
        let rows = try ordered().enumerated().filter { since == nil || $0.element.startedAt >= since! }.prefix(max(1, min(limit, 100)))
        guard !rows.isEmpty else { return "Aucune réunion enregistrée" + (since == nil ? "." : " depuis cette date.") }
        let jobs = try transcripts.latestJobs()
        return rows.map { index, row in
            "\(index + 1). \(date(row.startedAt)) · \(row.title) · \(duration(row)) · \(state(row, jobs[row.id]))"
        }.joined(separator: "\n")
    }

    /// One meeting and a page of its dialogue.
    public func meeting(_ which: String, page: Int) throws -> String {
        let row = try resolve(which)
        let lines = try transcripts.utterances(meetingID: row.id)
        var text = "# \(row.title)\n\(date(row.startedAt)) · \(duration(row)) · \(state(row, try transcripts.job(for: row.id))) · id \(row.id.uuidString.lowercased())\n"
        guard !lines.isEmpty else {
            return text + "\n" + (row.transcribedAt == nil ? "Pas encore transcrite." : "Personne n'a parlé, ou rien n'a pu être transcrit.")
        }
        let pages = (lines.count + Self.pageSize - 1) / Self.pageSize
        guard (1...pages).contains(page) else { throw ToolError("La page \(page) n'existe pas : \(pages) page\(pages > 1 ? "s" : "").") }
        let shown = lines[(page - 1) * Self.pageSize..<min(lines.count, page * Self.pageSize)]
        text += "\n" + shown.map { "[\(Self.timestamp($0.startMs))] \($0.speaker.label) : \($0.text)\($0.doubtful ? " (à vérifier)" : "")" }.joined(separator: "\n")
        text += "\n\n— page \(page) sur \(pages)"
        if page < pages { text += " ; la suite avec page = \(page + 1)" }
        return text
    }

    /// The lines that contain the words, grouped by meeting.
    public func search(_ query: String, limit: Int) throws -> String {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { throw ToolError("Le texte cherché doit avoir 2 caractères au moins.") }
        let hits = try transcripts.search(query, limit: max(1, min(limit, 100)))
        guard !hits.isEmpty else { return "Aucune transcription ne contient « \(query) »." }
        var order: [UUID] = []
        var byMeeting: [UUID: [SearchHit]] = [:]
        for hit in hits {
            if byMeeting[hit.meetingID] == nil { order.append(hit.meetingID) }
            byMeeting[hit.meetingID, default: []].append(hit)
        }
        return order.map { id in
            let hits = byMeeting[id] ?? []
            let first = hits[0]
            return "## \(first.title) — \(date(first.startedAt)) (id \(String(id.uuidString.lowercased().prefix(8))))\n"
                + hits.map { "[\(Self.timestamp($0.startMs))] \($0.speaker.label) : \($0.excerpt)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    // MARK: - Pieces

    func ordered() throws -> [MeetingRow] {
        try meetings.recent(limit: 100_000).filter { $0.status != .discarded }
    }

    /// A number from `reunions`, the start of an id, or a piece of the title (the most recent one).
    func resolve(_ which: String) throws -> MeetingRow {
        let rows = try ordered()
        let key = which.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(key), (1...rows.count).contains(number) { return rows[number - 1] }
        let lower = key.lowercased()
        if lower.count >= 4, let row = rows.first(where: { $0.id.uuidString.lowercased().hasPrefix(lower) }) { return row }
        if !key.isEmpty, let row = rows.first(where: { $0.title.range(of: key, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) {
            return row
        }
        throw ToolError("Aucune réunion ne correspond à « \(which) ». La liste : outil `reunions`.")
    }

    func state(_ row: MeetingRow, _ job: JobRow?) -> String {
        if row.status.isUnfinished { return "en cours d'enregistrement" }
        switch job?.state {
        case .done?: return job?.doubtful == true ? "transcrite, à vérifier" : "transcrite"
        case .running?: return "transcription en cours (\(Int(((job?.progress ?? 0) * 100).rounded())) %)"
        case .queued?: return "en file de transcription"
        case .failed?: return "transcription échouée"
        case nil: return row.transcribedAt == nil ? "pas encore transcrite" : "transcrite"
        }
    }

    func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }

    func duration(_ row: MeetingRow) -> String {
        let seconds = Int((row.endedAt ?? row.presumedEndAt ?? now()).timeIntervalSince(row.startedAt))
        let minutes = max(0, seconds) / 60
        return minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    static func timestamp(_ ms: Int) -> String {
        let total = ms / 1_000
        let (hours, minutes, seconds) = (total / 3_600, total / 60 % 60, total % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
