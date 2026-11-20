import Colin
import Combine
import Foundation
import GRDB
import Persistence

/// « À faire » on the Accueil (0.36.0, 18/11): what the list needs beside the projects and the events — who set each
/// deadline last, the first action left of each project — and Paul's two gestures, « Reporter » and « Livré », written
/// as his, with « Annuler » for a few seconds.
@MainActor public final class TodoLibrary: ObservableObject {
    /// A gesture just made, with what puts it back.
    public struct Settled: Equatable {
        public var undo: DueUndo
        /// « Cabinet Martin livré », « Cabinet Martin reporté à lundi ».
        public var text: String
        public var until: Date
    }

    /// The deadlines Paul set himself: never a call.
    @Published public private(set) var paulDeadlines: Set<UUID> = []
    /// The actions left of each project, in their order.
    @Published public private(set) var openActions: [UUID: [String]] = [:]

    /// The first action left of each project: what a folded line says without a task of the moment.
    public var firstActions: [UUID: String] { openActions.compactMapValues(\.first) }
    @Published public private(set) var settled: Settled?

    private let store: ProjectStore
    private let now: () -> Date
    private let givenCalendar: Calendar?
    private var calendar: Calendar { givenCalendar ?? CalendarView.calendar }
    /// How long « Annuler » stays.
    private let lasts: Duration
    private var observations: [AnyDatabaseCancellable] = []
    private var expiry: Task<Void, Never>?

    public init(database: AppDatabase, now: @escaping () -> Date = Date.init, calendar: Calendar? = nil, lasts: Duration = .seconds(8)) {
        store = ProjectStore(database)
        self.now = now
        givenCalendar = calendar
        self.lasts = lasts
        observations.append(ProjectChanges(database).observePaulDeadlines { [weak self] in self?.paulDeadlines = $0 })
        observations.append(store.observeOpenActions { [weak self] in self?.openActions = $0 })
    }

    deinit {
        expiry?.cancel()
    }

    /// The list, now.
    public func lines(projects: [ProjectRow], events: [CalendarEventRow]) -> [TodoRules.Line] {
        TodoRules.lines(projects: projects, events: events, paulDeadlines: paulDeadlines, firstActions: firstActions, now: now(), calendar: calendar)
    }

    /// « Livré »: « Livré le 18/11 » in the project's journal, and the deadline cleared — or, given the project's next
    /// visio (0.37.0), set to its day: a date taken from a meeting, which stays a visio. Its words are `TodoRules`'
    /// (lot 10, 20/11: the event is named `meeting`, as the guard of the words reads « call » in the strings).
    public func deliver(_ line: TodoRules.Line, next meeting: CalendarEventRow? = nil) {
        let date = now()
        let journal = TodoRules.delivered(date, calendar: calendar)
        guard let meeting else {
            set(line, to: nil, journal: journal, saying: "\(line.name) livré")
            return
        }
        set(line, to: calendar.startOfDay(for: meeting.startAt), journal: journal,
            saying: "\(line.name) livré · \(TodoRules.callWords(meeting.startAt, now: date, calendar: calendar))",
            by: store.signed(.paul, reason: "Livré", source: "event:\(meeting.id)"))
    }

    /// « Reporter » to one of its choices.
    public func postpone(_ line: TodoRules.Line, to choice: TodoRules.Postpone) {
        postpone(line, to: choice.date)
    }

    /// « Reporter » to a day picked in the calendar.
    public func postpone(_ line: TodoRules.Line, to date: Date) {
        let day = calendar.startOfDay(for: date)
        set(line, to: day, journal: nil, saying: "\(line.name) reporté à \(TodoRules.dayWord(day, now: now(), calendar: calendar))")
    }

    /// « Annuler »: the gesture put back, what changed since kept.
    public func undoSettled() {
        guard let settled else { return }
        try? store.revert(settled.undo, at: now())
        self.settled = nil
        expiry?.cancel()
    }

    private func set(_ line: TodoRules.Line, to due: Date?, journal: String?, saying text: String, by writer: ProjectStore? = nil) {
        let date = now()
        guard let undo = try? (writer ?? store).setDue(line.id, to: due, journal: journal, at: date) else { return }
        settled = Settled(undo: undo, text: text, until: date.addingTimeInterval(Double(lasts.components.seconds) + Double(lasts.components.attoseconds) / 1e18))
        expiry?.cancel()
        let lasts = lasts
        expiry = Task { [weak self] in
            try? await Task.sleep(for: lasts)
            guard !Task.isCancelled else { return }
            self?.settled = nil
        }
    }
}
