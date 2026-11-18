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

    @Published public private(set) var setters: [UUID: ChangeAuthor] = [:]
    @Published public private(set) var firstActions: [UUID: String] = [:]
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
        observations.append(ProjectChanges(database).observeDueSetters { [weak self] in self?.setters = $0 })
        observations.append(store.observeFirstOpenActions { [weak self] in self?.firstActions = $0 })
    }

    deinit {
        expiry?.cancel()
    }

    /// The list, now.
    public func lines(projects: [ProjectRow], events: [CalendarEventRow]) -> [TodoRules.Line] {
        TodoRules.lines(projects: projects, events: events, setters: setters, firstActions: firstActions, now: now(), calendar: calendar)
    }

    /// « Livré »: the deadline cleared, « Livré le 18/11 » in the project's journal.
    public func deliver(_ line: TodoRules.Line) {
        let date = now()
        set(line, to: nil, journal: TodoRules.delivered(date, calendar: calendar), saying: "\(line.name) livré")
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

    private func set(_ line: TodoRules.Line, to due: Date?, journal: String?, saying text: String) {
        let date = now()
        guard let undo = try? store.setDue(line.id, to: due, journal: journal, at: date) else { return }
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
