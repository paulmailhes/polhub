import AppKit
import Domain
import Foundation
import Pipeline
import GRDB
import Persistence
import Summarization

public struct DaySection: Equatable, Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let rows: [MeetingRow]
}

public enum MeetingListModel {
    /// Meetings by day, the latest first: « Aujourd'hui », « Hier », then « Mardi 10 novembre ».
    public static func sections(_ rows: [MeetingRow], now: Date, calendar: Calendar) -> [DaySection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale(identifier: "fr_FR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE d MMMM"
        let byDay = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.startedAt) }
        return byDay.keys.sorted(by: >).map { day in
            let title: String
            if day == today {
                title = "Aujourd'hui"
            } else if day == yesterday {
                title = "Hier"
            } else {
                let text = formatter.string(from: day)
                title = text.prefix(1).uppercased() + text.dropFirst()
            }
            return DaySection(title: title, rows: (byDay[day] ?? []).sorted { $0.startedAt > $1.startedAt })
        }
    }

    public static func durationText(_ row: MeetingRow, now: Date) -> String {
        if row.status.isUnfinished { return "en cours" }
        guard let end = row.endedAt else { return "—" }
        return DurationText.short(Int(end.timeIntervalSince(row.startedAt)))
    }

    /// « 14:00 · 52 min · Refonte du site »: the second line of a meeting in the list.
    public static func metaText(_ row: MeetingRow, project: String?, now: Date) -> String {
        ([row.startedAt.formatted(date: .omitted, time: .shortened), durationText(row, now: now)] + (project.map { [$0] } ?? []))
            .joined(separator: " · ")
    }

    /// The meeting to show: the one chosen while it exists, even older than the list (correctifs, 15/11), else the
    /// newest (Paul, 15/11: the newest meeting opens by itself). One sent to the Trash leaves its neighbour in
    /// `previous` open, as from the list. Nothing changes while the list is still empty.
    public static func meetingToOpen(selection: UUID?, rows: [MeetingRow], previous: [MeetingRow] = [],
                                     isGone: (UUID) -> Bool = { _ in true }) -> UUID? {
        guard !rows.isEmpty else { return selection }
        guard let selection else { return rows.first?.id }
        if rows.contains(where: { $0.id == selection }) || !isGone(selection) { return selection }
        let left = Set(rows.map(\.id))
        let before = previous.filter { $0.id == selection || left.contains($0.id) }
        if before.contains(where: { $0.id == selection }), let next = neighbor(of: selection, in: before) { return next }
        return rows.first?.id
    }

    /// The meeting to show once this one goes to the Trash: the one under it, else the one above.
    public static func neighbor(of id: UUID, in rows: [MeetingRow]) -> UUID? {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return rows.first?.id }
        if index + 1 < rows.count { return rows[index + 1].id }
        return index > 0 ? rows[index - 1].id : nil
    }

    /// The line about a meeting's summary in the list (15/11).
    public struct SummaryLine: Equatable, Sendable {
        public enum Kind: Sendable { case ready, writing, waiting, failed }
        public var text: String
        public var kind: Kind
    }

    /// Its first lines when it is written; otherwise where it is. Nothing before it is asked, nor when there were
    /// too few words.
    public static func summaryLine(overview: String?, job: SummaryJobRow?) -> SummaryLine? {
        if job?.state == .running { return SummaryLine(text: overview ?? "Compte rendu en cours d'écriture…", kind: .writing) }
        if let overview { return SummaryLine(text: overview, kind: .ready) }
        switch job?.state {
        case .failed?: return SummaryLine(text: "Le compte rendu n'a pas pu se faire", kind: .failed)
        case .queued?: return SummaryLine(text: "Compte rendu en attente", kind: .waiting)
        default: return nil
        }
    }
}

/// The meetings and the journal, kept up to date from the base.
@MainActor
public final class MeetingLibrary: ObservableObject {
    @Published public private(set) var rows: [MeetingRow] = []
    @Published public private(set) var journal: [JournalEntry] = []
    /// The newest job of each meeting.
    @Published public private(set) var jobs: [UUID: JobRow] = [:]
    /// From the pop-up to the end of a meeting: transcriptions wait.
    @Published public var meetingActive = false
    public let store: MeetingStore
    public let transcripts: TranscriptStore
    /// Set by the app: « Réessayer » and « Retranscrire » go through it.
    public var queue: TranscriptionQueue?
    /// Set by the app: « Refaire le compte rendu » goes through it (14/11); its progress part by part shows on the
    /// meeting's page (15/11).
    public var summaries: SummaryQueue? {
        didSet { follow(summaries) }
    }
    /// Why no summary can be made (Apple Intelligence off…), said on the meeting's page.
    @Published public var summaryUnavailable: String?
    /// The first lines of each meeting's summary, for the list (15/11).
    @Published public private(set) var overviews: [UUID: String] = [:]
    /// How each meeting's summary went, for the list (15/11).
    @Published public private(set) var summaryJobs: [UUID: SummaryJobRow] = [:]
    /// Where the summary under way is, part by part.
    @Published public private(set) var summaryProgress: [UUID: SummaryProgress] = [:]
    private var observations: [AnyDatabaseCancellable] = []
    private var progressTask: Task<Void, Never>?

    public init(store: MeetingStore) {
        self.store = store
        transcripts = TranscriptStore(store.database)
        observations.append(store.observeRecent(limit: 500) { [weak self] rows in self?.rows = rows })
        observations.append(store.observeJournal(limit: 300) { [weak self] entries in self?.journal = entries })
        observations.append(transcripts.observeLatestJobs { [weak self] jobs in self?.jobs = jobs })
        observations.append(store.observeSummaries(limit: 500, digest: { SummaryText.overview($0) }) { [weak self] overviews in
            self?.overviews = overviews
        })
        observations.append(SummaryStore(store.database).observeJobs { [weak self] jobs in self?.summaryJobs = jobs })
    }

    private func follow(_ queue: SummaryQueue?) {
        progressTask?.cancel()
        guard let queue else { return }
        progressTask = Task { [weak self] in
            for await update in queue.progress {
                guard let self else { return }
                self.summaryProgress[update.meetingID] = update.progress
            }
        }
    }

    /// A meeting of the list, or an older one the list does not hold (it keeps the 500 newest); nothing for one in
    /// the Trash (correctifs, 15/11).
    public func row(_ id: UUID) -> MeetingRow? {
        if let row = rows.first(where: { $0.id == id }) { return row }
        return (try? store.meeting(id: id)).flatMap { $0.deletedAt == nil ? $0 : nil }
    }

    /// The meeting is in the Trash, or not in the base.
    public func isGone(_ id: UUID) -> Bool {
        row(id) == nil
    }

    /// « Supprimer… »: the meeting goes to the Trash with its audio, where it can still be found (14/11).
    public func moveToTrash(_ row: MeetingRow, folder: URL) {
        let queue = queue, id = row.id
        Task { await queue?.forget(meetingID: id) }
        try? store.softDelete(id: id, at: .now)
        NSWorkspace.shared.recycle([folder])
    }
}
