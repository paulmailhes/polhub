import Domain
import Foundation
import Persistence

/// The projects as text, and the four writes a session may make: what the project tools of `polhub mcp`
/// answer. Same vocabulary as the `obsidian` server they replace (13/11). The status, due date and « todo »
/// of a project belong to Paul: nothing here changes them.
public struct ProjectDesk: Sendable {
    public static let briefActions = 15
    /// The order of `projets`, as in the `obsidian` server: priorities first, done last.
    static let listOrder: [ProjectStatus] = [.priorite1, .priorite2, .priorite3, .enAttente, .idee, .none, .termine]
    let projects: ProjectStore
    let meetings: MeetingStore
    let reader: MeetingReader
    /// The session's folder: a project whose code folder contains it is the default project.
    let workingDirectory: String?
    let now: @Sendable () -> Date
    let timeZone: TimeZone

    public init(projects: ProjectStore, meetings: MeetingStore, workingDirectory: String?, now: @escaping @Sendable () -> Date = Date.init,
                timeZone: TimeZone = .current) {
        self.projects = projects
        self.meetings = meetings
        self.reader = MeetingReader(meetings: meetings, transcripts: TranscriptStore(projects.database), now: now, timeZone: timeZone)
        self.workingDirectory = workingDirectory
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: - Reading

    /// All the projects, grouped by status in the board's order.
    public func list(filter: String?) throws -> String {
        let here = try? folderProject()
        let all = try projects.projects().filter { project in
            guard let filter = filter?.trimmingCharacters(in: .whitespaces), !filter.isEmpty else { return true }
            return [project.name, project.client ?? "", project.status.label].contains { Self.contains($0, filter) }
        }
        guard !all.isEmpty else { return filter == nil ? "Aucun projet." : "Aucun projet ne correspond à « \(filter!) »." }
        var lines: [String] = []
        for status in Self.listOrder {
            let group = all.filter { $0.status == status }
            guard !group.isEmpty else { continue }
            lines.append("## \(status.label) (\(group.count))")
            for project in group {
                var parts = [project.name]
                if let client = project.client, !client.isEmpty { parts.append(client) }
                if let due = project.dueDate { parts.append("échéance \(day(due))") }
                if let folder = Self.folderPath(project.codeFolder) { parts.append("dossier \(folder)") }
                lines.append("- " + parts.joined(separator: " · ") + (project.id == here?.id ? "  ← ce dossier" : ""))
            }
            lines.append("")
        }
        if here == nil, let workingDirectory { lines.append("Le dossier de la session (\(workingDirectory)) n'est lié à aucun projet.") }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The brief of a project, in one page.
    public func context(_ which: String?, all: Bool) throws -> String {
        let project = try resolve(which)
        var text = "# \(project.name)\n"
        var facts = ["statut : \(project.status.label)"]
        if let client = project.client, !client.isEmpty { facts.append("client : \(client)") }
        if let due = project.dueDate { facts.append("échéance : \(day(due))") }
        if let folder = Self.folderPath(project.codeFolder) { facts.append("dossier : \(folder)") }
        text += facts.joined(separator: " · ") + "\n"
        if let todo = project.todo, !todo.isEmpty { text += "À faire maintenant : \(todo)\n" }
        if !project.contacts.isEmpty { text += "Contacts : \(project.contacts.joined(separator: ", "))\n" }

        let open = try openActions(project)
        text += "\n## Actions ouvertes (\(open.count))\n"
        let shown = all ? open : Array(open.prefix(Self.briefActions))
        text += shown.isEmpty ? "Aucune.\n" : shown.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n") + "\n"
        if shown.count < open.count { text += "… et \(open.count - shown.count) autres (outil `actions`).\n" }

        let filed = try numberedMeetings(project).prefix(5)
        text += "\n## Réunions récentes\n"
        text += filed.isEmpty ? "Aucune réunion rangée dans ce projet.\n" : filed.map { "\($0.number). \(reader.date($0.row.startedAt)) · \($0.row.title)" }.joined(separator: "\n") + "\n"

        let notes = project.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { text += "\n## Notes\n\(notes)\n" }

        let journal = try projects.journal(projectID: project.id).prefix(5)
        if !journal.isEmpty {
            text += "\n## Journal (les 5 dernières entrées)\n"
            text += journal.map { "### \(day($0.date)) — \($0.title)\n\($0.body)" }.joined(separator: "\n\n") + "\n"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The open actions, numbered for `fait`; with `all`, the done ones after them, unnumbered.
    public func actions(_ which: String?, all: Bool) throws -> String {
        let project = try resolve(which)
        let open = try openActions(project)
        var text = "Actions ouvertes de « \(project.name) » (\(open.count))\n"
        text += open.isEmpty ? "Aucune." : open.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
        if all {
            let done = try projects.actions(projectID: project.id).filter(\.done)
            if !done.isEmpty { text += "\n\nFaites (\(done.count))\n" + done.map { "✓ \($0.text)" }.joined(separator: "\n") }
        }
        return text
    }

    /// The meetings filed in the project, with their number in `reunions`.
    public func meetings(_ which: String?) throws -> String {
        let project = try resolve(which)
        let filed = try numberedMeetings(project)
        guard !filed.isEmpty else { return "Aucune réunion rangée dans « \(project.name) »." }
        let jobs = try TranscriptStore(projects.database).latestJobs()
        return "Réunions de « \(project.name) »\n" + filed.map {
            "\($0.number). \(reader.date($0.row.startedAt)) · \($0.row.title) · \(reader.duration($0.row)) · \(reader.state($0.row, jobs[$0.row.id]))"
        }.joined(separator: "\n")
    }

    /// The projects whose name, client, notes, actions or journal contain the text; `nil` when none does.
    public func search(_ query: String) throws -> String? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var blocks: [String] = []
        for project in try projects.projects() {
            var hits: [String] = []
            if Self.contains(project.name, query) || Self.contains(project.client ?? "", query) { hits.append("(nom ou client)") }
            hits += project.notes.components(separatedBy: "\n").filter { Self.contains($0, query) }.map { "note : \($0.trimmingCharacters(in: .whitespaces))" }
            hits += try projects.actions(projectID: project.id).filter { Self.contains($0.text, query) }
                .map { "action\($0.done ? " faite" : "") : \($0.text)" }
            hits += try projects.journal(projectID: project.id).filter { Self.contains($0.title, query) || Self.contains($0.body, query) }
                .map { "journal du \(day($0.date)) : \($0.title)" }
            if !hits.isEmpty { blocks.append("## \(project.name)\n" + hits.prefix(10).map { "- \($0)" }.joined(separator: "\n")) }
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
    }

    // MARK: - The four writes

    public func addAction(_ which: String?, text: String) throws -> String {
        let project = try resolve(which)
        let text = try Self.required(text, "texte", "ce qu'il reste à faire")
        let last = try projects.actions(projectID: project.id).map(\.position).max() ?? -1
        try projects.saveAction(ActionRow(projectID: project.id, text: text, addedOn: now(), position: last + 1, createdAt: now()))
        return "Action ajoutée à « \(project.name) » : \(text)"
    }

    public func done(_ which: String?, numbers: [Int]) throws -> String {
        let project = try resolve(which)
        let open = try openActions(project)
        guard !numbers.isEmpty else { throw ToolError("Il manque « numeros » : les numéros affichés par `actions`.") }
        if let wrong = numbers.first(where: { !(1...max(1, open.count)).contains($0) || open.isEmpty }) {
            throw ToolError("L'action \(wrong) n'existe pas : « \(project.name) » a \(open.count) action\(open.count > 1 ? "s" : "") ouverte\(open.count > 1 ? "s" : ""). Voir `actions`.")
        }
        var checked: [String] = []
        for number in Set(numbers).sorted() {
            var action = open[number - 1]
            action.done = true
            action.updatedAt = now()
            try projects.saveAction(action)
            checked.append(action.text)
        }
        return "Coché dans « \(project.name) » : " + checked.joined(separator: " ; ")
    }

    /// A dated bullet at the end of the notes' first part (the vault's « Notes » section).
    public func addNote(_ which: String?, text: String) throws -> String {
        var project = try resolve(which)
        let text = try Self.required(text, "texte", "la note")
        let bullet = "- \(day(now())) : \(text)"
        let notes = project.notes
        if let heading = notes.range(of: "\n## ") ?? (notes.hasPrefix("## ") ? notes.startIndex..<notes.startIndex : nil) {
            let head = String(notes[..<heading.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = String(notes[heading.lowerBound...]).trimmingCharacters(in: .newlines)
            project.notes = (head.isEmpty ? bullet : head + "\n" + bullet) + "\n\n" + rest
        } else {
            let head = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            project.notes = head.isEmpty ? bullet : head + "\n" + bullet
        }
        project.updatedAt = now()
        try projects.saveNotes(project)
        return "Note ajoutée à « \(project.name) »."
    }

    public func addJournal(_ which: String?, title: String, details: [String]) throws -> String {
        let project = try resolve(which)
        let title = try Self.required(title, "titre", "le titre de l'étape")
        let body = details.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { "- \($0)" }.joined(separator: "\n")
        try projects.addJournal(ProjectJournalRow(projectID: project.id, date: now(), title: title, body: body, createdAt: now()))
        return "Journal de « \(project.name) » : \(title)"
    }

    // MARK: - Which project

    /// A name (case and accents ignored), a piece of one name, or else the session's folder.
    func resolve(_ which: String?) throws -> ProjectRow {
        guard let key = which?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return try folderProject() }
        let all = try projects.projects()
        if let exact = all.first(where: { Self.fold($0.name) == Self.fold(key) }) { return exact }
        let matches = all.filter { Self.contains($0.name, key) }
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw ToolError("Aucun projet ne s'appelle « \(key) ». La liste : outil `projets`.") }
        throw ToolError("« \(key) » désigne plusieurs projets : " + matches.map(\.name).joined(separator: ", ") + ". Donne le nom exact.")
    }

    func folderProject() throws -> ProjectRow {
        guard let workingDirectory else { throw ToolError("Précise « projet » : le nom d'un projet (outil `projets`).") }
        let here = Self.normalized(workingDirectory)
        let linked = try projects.projects().compactMap { project -> (ProjectRow, String)? in
            guard let folder = Self.folderPath(project.codeFolder).map(Self.normalized) else { return nil }
            return here == folder || here.hasPrefix(folder + "/") ? (project, folder) : nil
        }
        guard let best = linked.max(by: { $0.1.count < $1.1.count }) else {
            throw ToolError("Le dossier \(workingDirectory) n'est lié à aucun projet : précise « projet » (outil `projets`).")
        }
        return best.0
    }

    // MARK: - Pieces

    func openActions(_ project: ProjectRow) throws -> [ActionRow] {
        try projects.actions(projectID: project.id).filter { !$0.done }
    }

    func numberedMeetings(_ project: ProjectRow) throws -> [(number: Int, row: MeetingRow)] {
        try reader.ordered().enumerated().filter { $0.element.projectID == project.id }.map { ($0.offset + 1, $0.element) }
    }

    func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    /// A code folder as a plain path: the vault has both `file:///…` and plain paths.
    static func folderPath(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("file://"), let url = URL(string: value) { return url.path(percentEncoded: false) }
        return value
    }

    static func normalized(_ path: String) -> String {
        var path = (path as NSString).expandingTildeInPath
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    static func contains(_ text: String, _ piece: String) -> Bool {
        !piece.isEmpty && fold(text).contains(fold(piece))
    }

    static func required(_ value: String, _ name: String, _ what: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ToolError("Il manque « \(name) » : \(what).") }
        return value
    }
}
