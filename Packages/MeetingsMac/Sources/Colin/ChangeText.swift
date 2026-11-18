import Foundation
import Persistence

/// One field of a change, as a small card says it: before → after (the Accueil's pass, 18/11).
public struct ChangeField: Equatable, Sendable {
    public var label: String
    public var before: String?
    public var after: String?

    public init(label: String, before: String?, after: String?) {
        self.label = label
        self.before = before
        self.after = after
    }
}

/// How a change of a project reads on the Accueil (step 3, 18/11): one sentence, the project first, what it was and
/// what it became, then « Annuler ». Plain text: what an agent wrote is never a link.
public enum ChangeText {
    /// A line by field, in the journal's order: the card of a change.
    public static func fields(_ line: ProjectChangeLine, calendar: Calendar) -> [ChangeField] {
        line.rows.compactMap { row in
            switch row.field {
            case .status: ChangeField(label: "Statut", before: row.before, after: row.after)
            case .dueDate: ChangeField(label: "Échéance", before: row.before.flatMap { day($0, calendar) }, after: row.after.flatMap { day($0, calendar) })
            case .todo: ChangeField(label: "Tâche", before: text(row.before), after: text(row.after))
            case .client: ChangeField(label: "Client", before: text(row.before), after: text(row.after))
            case .notes: ChangeField(label: "Notes", before: nil, after: "réécrites")
            case .actionAdded: ChangeField(label: "Action", before: nil, after: row.after)
            case .actionDone: ChangeField(label: "Action", before: actionText(row), after: row.after == "1" ? "faite" : "à faire")
            case .actionText: ChangeField(label: "Action", before: row.before, after: row.after)
            case .actionRemoved: ChangeField(label: "Action", before: row.before, after: nil)
            case .journalAdded: ChangeField(label: "Journal", before: nil, after: row.after)
            }
        }
    }

    public static func sentence(_ line: ProjectChangeLine, calendar: Calendar) -> String {
        var parts: [String] = []
        let rows = line.rows
        for field in ProjectChangeField.allCases {
            let of = rows.filter { $0.field == field }
            guard let first = of.first else { continue }
            switch field {
            case .status:
                parts.append("\(first.before ?? "?") → \(of.last?.after ?? "?")")
            case .dueDate:
                let before = first.before.flatMap { day($0, calendar) }, after = of.last?.after.flatMap { day($0, calendar) }
                switch (before, after) {
                case (_, nil): parts.append("échéance retirée")
                case let (nil, after?): parts.append("échéance \(after)")
                case let (before?, after?): parts.append("échéance \(before) → \(after)")
                }
            case .todo:
                parts.append(text(of.last?.after).map { "tâche « \($0) »" } ?? "tâche retirée")
            case .client:
                parts.append(text(of.last?.after).map { "client « \($0) »" } ?? "client retiré")
            case .notes:
                parts.append("notes réécrites")
            case .actionAdded:
                parts.append(of.count == 1 ? "action « \(first.after ?? "") » ajoutée" : "\(of.count) actions ajoutées")
            case .actionDone:
                let checked = of.filter { $0.after == "1" }, unchecked = of.filter { $0.after != "1" }
                if checked.count == 1 { parts.append("action « \(actionText(checked[0])) » cochée") }
                if checked.count > 1 { parts.append("\(checked.count) actions cochées") }
                if unchecked.count == 1 { parts.append("action « \(actionText(unchecked[0])) » décochée") }
                if unchecked.count > 1 { parts.append("\(unchecked.count) actions décochées") }
            case .actionText:
                parts.append(of.count == 1 ? "action reformulée, « \(first.after ?? "") »" : "\(of.count) actions reformulées")
            case .actionRemoved:
                parts.append(of.count == 1 ? "action « \(first.before ?? "") » retirée" : "\(of.count) actions retirées")
            case .journalAdded:
                parts.append(of.count == 1 ? "journal « \(first.after ?? "") »" : "\(of.count) entrées au journal")
            }
        }
        return "« \(line.projectName) » : " + parts.joined(separator: ", ") + "."
    }

    /// Why it was made, said apart in small: a rule's event.
    public static func note(_ line: ProjectChangeLine) -> String? { line.reason }

    /// Who made it and when, then why: « Colin, aujourd'hui 10:42 · Après ton mail à Claire, 9:50 ».
    public static func byline(_ line: ProjectChangeLine, now: Date, calendar: Calendar) -> String {
        let who = switch line.who {
        case .colin: "Colin"
        case .agent: "Un agent"
        case .paul: "Toi"
        }
        let said = "\(who), \(Briefing.dayLabel(line.at, now: now, calendar: calendar))"
        return line.reason.map { "\(said) · \($0)" } ?? said
    }

    /// What « Annuler » did.
    public static func undone(_ outcome: UndoOutcome) -> String {
        switch outcome {
        case .undone: "Annulé."
        case .partly: "Annulé, sauf ce qui a changé depuis."
        case .changedSince: "Rien à annuler : ça a changé depuis."
        }
    }

    private static func text(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func actionText(_ row: ProjectChangeRow) -> String {
        let detail = row.detail.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        return detail?["text"] as? String ?? ""
    }

    /// A date as the base keeps it (UTC, « 2026-11-18 23:00:00.000 »), said as a day here: « 19/11 ».
    static func day(_ stored: String, _ calendar: Calendar) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: stored) { return KanbanRules.day(date, calendar) }
        }
        return nil
    }
}
