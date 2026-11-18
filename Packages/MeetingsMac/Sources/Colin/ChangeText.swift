import Foundation
import Persistence

/// How a change of a project reads on the Accueil (step 3, 18/11): one sentence, the project first, what it was and
/// what it became, then « Annuler ». Plain text: what an agent wrote is never a link.
public enum ChangeText {
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
