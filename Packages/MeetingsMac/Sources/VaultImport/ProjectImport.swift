import Domain
import Foundation
import Persistence

public struct ImportReport: Equatable, Sendable {
    public let projects: Int
    public let actions: Int
    public let journalEntries: Int
    public let withoutStatus: Int
    public let warnings: [String]

    /// « 69 projets, 312 actions, 48 entrées de journal ; 1 sans statut ; 1 avertissement ».
    public var summary: String {
        func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n > 1 ? many : one)" }
        var parts = [count(projects, "projet", "projets"), count(actions, "action", "actions"),
                     count(journalEntries, "entrée de journal", "entrées de journal")].joined(separator: ", ")
        if withoutStatus > 0 { parts += " ; \(withoutStatus) sans statut" }
        if !warnings.isEmpty { parts += " ; " + count(warnings.count, "avertissement", "avertissements") }
        return parts
    }
}

/// The import of the vault's projects into the app's base: read, then replace everything in one go.
public enum ImportError: Error, CustomStringConvertible {
    case emptyVault

    public var description: String {
        switch self {
        case .emptyVault: "Le coffre ne contient aucun projet (synchronisation en cours ?) : rien n'a été remplacé."
        }
    }
}

public enum ProjectImport {
    public static func run(vault: URL, store: ProjectStore, now: Date) throws -> ImportReport {
        try apply(VaultReader.read(vault: vault), store: store, now: now)
    }

    /// Replaces the app's projects with those read; a vault without any project replaces nothing.
    public static func apply(_ snapshot: VaultSnapshot, store: ProjectStore, now: Date) throws -> ImportReport {
        guard !snapshot.projects.isEmpty else { throw ImportError.emptyVault }
        var projects: [ProjectRow] = []
        var actions: [ActionRow] = []
        var journal: [ProjectJournalRow] = []
        let grouped = Dictionary(grouping: snapshot.projects) { ProjectStatus(obsidian: $0.status) }
        for (status, members) in grouped {
            let order = snapshot.cardOrder[status.rawValue] ?? []
            let sorted = members.sorted { a, b in
                switch (order.firstIndex(of: a.name), order.firstIndex(of: b.name)) {
                case let (i?, j?): i < j
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
            for (rank, imported) in sorted.enumerated() {
                let project = ProjectRow(
                    name: imported.name, status: status, client: imported.client, dueDate: imported.dueDate, todo: imported.todo,
                    icon: imported.icon, color: imported.color, contacts: imported.contacts, createdOn: imported.createdOn,
                    codeFolder: imported.codeFolder, github: imported.github, notion: imported.notion, lastActivity: imported.lastActivity,
                    lastMeetingImported: snapshot.lastMeetings[imported.name], noteModifiedAt: imported.noteModifiedAt,
                    notes: imported.notes, kanbanOrder: Double(rank), importedFrom: imported.relativePath, createdAt: now
                )
                projects.append(project)
                actions += imported.actions.enumerated().map { index, action in
                    ActionRow(projectID: project.id, text: action.text, done: action.done, addedOn: action.addedOn,
                              position: Double(index), createdAt: now)
                }
                journal += imported.journal.map { entry in
                    ProjectJournalRow(projectID: project.id, date: entry.date, title: entry.title, body: entry.body, createdAt: now)
                }
            }
        }
        try store.replaceAll(projects, actions: actions, journal: journal)
        return ImportReport(
            projects: projects.count, actions: actions.count, journalEntries: journal.count,
            withoutStatus: projects.filter { $0.status == ProjectStatus.none }.count, warnings: snapshot.warnings
        )
    }
}
