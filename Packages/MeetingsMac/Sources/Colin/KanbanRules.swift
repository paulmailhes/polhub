import Domain
import Foundation
import Persistence
import PolhubDesign

/// « Colin tient le kanban seul » (step 3, 18/11): two rules, no model, nothing that leaves the Mac. What they return
/// is written by the app, signed Colin's, each change with « Annuler ».
public enum KanbanRules {
    /// A mail older than this is no longer « just sent ».
    static let sentLasts: TimeInterval = 7 * 86_400

    /// After a mail Paul sends in a thread of a project (or a new mail to its people): the card passes from « priorité
    /// 2 » to « priorité 1 », its task becomes « Attend le retour de X », a line goes to its journal. A project in
    /// pause or finished is left: leaving them is Paul's to say. What Paul changed himself today stays. `projectOf`: the
    /// project of each thread, as « À valider » reads it; `since`: when the switch was turned on.
    public static func afterSends(_ exchanges: [MailExchange], projectOf: [String: UUID], projects: [ProjectRow], mine: Set<String>, since: Date,
                                  known: Set<String>, touched: Set<ProjectFieldKey>, now: Date, calendar: Calendar) -> [KanbanEdit] {
        var cards = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var edits: [KanbanEdit] = []
        var answered = known
        let floor = max(since, now.addingTimeInterval(-sentLasts))
        for mail in exchanges.sorted(by: { $0.date < $1.date }) {
            guard mail.mine, !mail.calendar, !mail.automatic, mail.date > floor, mail.date <= now, !mail.messageKey.isEmpty else { continue }
            let source = "mail:\(mail.messageKey)"
            guard !answered.contains(source), let id = projectOf[mail.threadKey], var card = cards[id], card.deletedAt == nil,
                  [.priorite1, .priorite2].contains(card.status),
                  let person = mail.recipients.first(where: { !mine.contains($0) }) else { continue }
            let name = Self.person(mail.names[person] ?? person)
            let to = name.map { " à \($0)" } ?? ""
            var edit = KanbanEdit(projectID: id, status: nil, todo: nil, dueDate: nil, journal: "Mail envoyé\(to) le \(day(mail.date, calendar))",
                                  reason: "Après ton mail\(to), \(Briefing.time(mail.date, calendar: calendar))", source: source)
            if card.status == .priorite2, !touched.contains(ProjectFieldKey(projectID: id, field: .status)) {
                edit.status = .priorite1
                card.status = .priorite1
            }
            // « Attend le retour de Marc », as Réglages › Colin says it (lot 10, 20/11: « En attente retour de … »).
            let task = name.map { "Attend le retour \(Words.of($0))" } ?? "Attend un retour"
            if card.todo != task, !touched.contains(ProjectFieldKey(projectID: id, field: .todo)) {
                edit.todo = task
                card.todo = task
            }
            cards[id] = card
            answered.insert(source)
            edits.append(edit)
        }
        return edits
    }

    /// A meeting booked in a project becomes its deadline when it has none, or a past one: the next one to come, Paul
    /// not having declined it, not a whole day. A project in pause or finished is left; a deadline Paul changed today
    /// too.
    public static func afterBookings(_ events: [CalendarEventRow], projects: [ProjectRow], now: Date, known: Set<String>, touched: Set<ProjectFieldKey>,
                                     calendar: Calendar) -> [KanbanEdit] {
        let today = calendar.startOfDay(for: now)
        let coming = events
            .filter { $0.projectID != nil && !$0.allDay && $0.startAt > now && $0.attendees.first(where: \.isSelf)?.response != "declined" }
            .sorted { $0.startAt < $1.startAt }
        var edits: [KanbanEdit] = []
        for project in projects where project.deletedAt == nil && [.priorite1, .priorite2].contains(project.status) {
            if let due = project.dueDate, due >= today { continue }
            guard !touched.contains(ProjectFieldKey(projectID: project.id, field: .dueDate)),
                  let next = coming.first(where: { $0.projectID == project.id }) else { continue }
            let source = "event:\(next.id)"
            guard !known.contains(source) else { continue }
            let weekday = Briefing.weekday(next.startAt, calendar: calendar)
            edits.append(KanbanEdit(projectID: project.id, status: nil, todo: nil, dueDate: calendar.startOfDay(for: next.startAt), journal: nil,
                                    reason: "Rendez-vous du \(weekday) \(day(next.startAt, calendar))", source: source))
        }
        return edits
    }

    /// Who a mail was sent to, as the task and the journal say it (final review, 18/11): the name comes from a header a
    /// third party wrote, and the task is read by the agents as « À faire maintenant ». Only a first name (letters,
    /// hyphens, apostrophes, 24 at most) or a plain address goes in; anything else, no name.
    static func person(_ header: String) -> String? {
        let name = ReviewRules.short(header)
        let letters = CharacterSet.letters.union(CharacterSet(charactersIn: "-'’"))
        if (1...24).contains(name.count), name.unicodeScalars.allSatisfy(letters.contains), name.first?.isLetter == true { return name }
        let address = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._%+-@")
        if (3...48).contains(name.count), name.contains("@"), name.lowercased().unicodeScalars.allSatisfy(address.contains) { return name.lowercased() }
        return nil
    }

    /// « 18 nov. », « 1er déc. », by `Words` (lot 10, 20/11: « 18/11 »).
    static func day(_ date: Date, _ calendar: Calendar) -> String {
        Words.shortDate(date, now: date, calendar: calendar)
    }
}
