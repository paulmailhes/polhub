import Domain
import Foundation
import Persistence

/// The projects as text, and the writes a session may make: what the project tools of `polhub mcp` answer. Same
/// vocabulary as the `obsidian` server they replace (13/11). Since 16/11, the status, due date and task of the
/// moment change too, when Paul asks (`update`), and an action can be reworded or removed (`editAction`); a
/// project is created (`create`), its client, notes and contacts change (`update`).
public struct ProjectDesk: Sendable {
    public static let briefActions = 15
    /// The order of `projets`, as in the `obsidian` server: priorities first, done last.
    static let listOrder: [ProjectStatus] = ProjectStatus.allCases
    /// A new project's status when none is given, as on the board.
    static let newProjectStatus = ProjectStatus.priorite1
    let projects: ProjectStore
    let meetings: MeetingStore
    let reader: MeetingReader
    /// The session's folder: a project whose code folder contains it is the default project.
    let workingDirectory: String?
    /// The folder of Polhub's data, beside the base (`AppPaths.root`): where Inspiration's images are read.
    let dataRoot: URL?
    let now: @Sendable () -> Date
    let timeZone: TimeZone
    /// Paul's home folder: a new project's code folder is never it, nor above it (review of 16/11).
    let home: URL

    public init(projects: ProjectStore, meetings: MeetingStore, workingDirectory: String?, dataRoot: URL? = nil,
                now: @escaping @Sendable () -> Date = Date.init, timeZone: TimeZone = .current,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.projects = projects
        self.meetings = meetings
        self.reader = MeetingReader(meetings: meetings, transcripts: TranscriptStore(projects.database), now: now, timeZone: timeZone)
        self.workingDirectory = workingDirectory
        self.dataRoot = dataRoot
        self.now = now
        self.timeZone = timeZone
        self.home = home
    }

    /// « Inspiration » (sites, branding, mock-ups), read from the same base (16/11).
    public var inspiration: InspirationDesk {
        InspirationDesk(store: InspirationStore(projects.database), dataRoot: dataRoot, timeZone: timeZone)
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
        // The linked contacts (base v4), else the vault's names.
        let linked = (try? ContactStore(projects.database).contacts(projectID: project.id)) ?? []
        if !linked.isEmpty {
            text += "Contacts : " + linked.map { contact in
                let details = [contact.company, contact.email].compactMap { $0 }
                return details.isEmpty ? contact.name : "\(contact.name) (\(details.joined(separator: ", ")))"
            }.joined(separator: " ; ") + "\n"
        } else if !project.contacts.isEmpty {
            text += "Contacts : \(project.contacts.joined(separator: ", "))\n"
        }

        // Step « Agents »: only how many, the mails themselves through `mails`.
        if let mails = MailDesk(database: projects.database, root: URL(fileURLWithPath: "/"), scope: .tout, projects: nil, now: now)
            .count(projectID: project.id), mails.threads > 0 {
            text += "Mails : \(mails.threads) fil\(mails.threads > 1 ? "s" : "") ces 30 derniers jours"
                + (mails.unread > 0 ? ", dont \(mails.unread) non lu\(mails.unread > 1 ? "s" : "")" : "") + " (outil `mails` avec ce projet).\n"
        }

        let open = try openActions(project)
        text += "\n## Actions ouvertes (\(open.count))\n"
        let shown = all ? open : Array(open.prefix(Self.briefActions))
        text += shown.isEmpty ? "Aucune.\n" : shown.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n") + "\n"
        if shown.count < open.count { text += "… et \(open.count - shown.count) autres (outil `actions`).\n" }

        let coming = ((try? CalendarStore(projects.database).events(projectID: project.id)) ?? []).filter { $0.endAt > now() }.prefix(5)
        if !coming.isEmpty {
            text += "\n## Prochains rendez-vous\n" + coming.map { "- \(reader.date($0.startAt)) · \($0.title)" }.joined(separator: "\n") + "\n"
        }

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
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
        let project = try resolve(which)
        let text = try Self.required(text, "texte", "ce qu'il reste à faire")
        let last = try projects.actions(projectID: project.id).map(\.position).max() ?? -1
        try projects.saveAction(ActionRow(projectID: project.id, text: text, addedOn: now(), position: last + 1, createdAt: now()))
        return "Action ajoutée à « \(project.name) » : \(text)"
    }

    public func done(_ which: String?, numbers: [Int]) throws -> String {
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
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
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
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
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
        let project = try resolve(which)
        let title = try Self.required(title, "titre", "le titre de l'étape")
        let body = details.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map { "- \($0)" }.joined(separator: "\n")
        try projects.addJournal(ProjectJournalRow(projectID: project.id, date: now(), title: title, body: body, createdAt: now()))
        return "Journal de « \(project.name) » : \(title)"
    }

    // MARK: - What Paul asks to change (16/11)

    /// The status, the due date (« AAAA-MM-JJ », or « aucune »), the task of the moment (empty or « aucune »
    /// clears it), when Paul asks a session (16/11: « il m'a dit qu'il avait pas les droits »). Only the fields
    /// given change; a new status puts the project on top of its column, as on the board (19/11).
    /// Paul's 7 (16/11): the client too (empty or « aucun » clears it), the notes replaced whole (empty notes are no
    /// notes given: nothing is wiped), a contact linked (`contact`) or taken out (`removeContact`) as Paul does it
    /// on the project's page. Everything is read before anything is written: a refusal changes nothing.
    public func update(_ which: String?, status: String?, due: String?, todo: String?, client: String? = nil, notes: String? = nil,
                       contact: String? = nil, removeContact: String? = nil) throws -> String {
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
        let project = try resolve(which)
        var said: [String] = []
        var newStatus: ProjectStatus?
        if let status = Self.given(status) {
            let value = try Self.status(status)
            newStatus = value
            said.append("statut \(value.label)")
        }
        var edited = project
        if let due = Self.given(due) {
            edited.dueDate = try dueDate(due)
            said.append(edited.dueDate.map { "échéance \(day($0))" } ?? "sans échéance")
        }
        if let todo {
            let text = todo.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || Self.fold(text) == "aucune" {
                edited.todo = nil
                said.append("sans tâche du moment")
            } else {
                edited.todo = text
                said.append("tâche du moment « \(text) »")
            }
        }
        if let client {
            edited.client = Self.clientName(client)
            said.append(edited.client.map { "client « \($0) »" } ?? "sans client")
        }
        let newNotes = Self.given(notes)
        // The notes Paul had are kept whole in the journal, so that he can take them back (review of 16/11).
        let oldNotes = project.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepsOldNotes = newNotes.map { !oldNotes.isEmpty && $0 != oldNotes } ?? false
        if let newNotes {
            said.append(oldNotes.isEmpty ? "notes écrites" : "notes remplacées (\(project.notes.count) → \(newNotes.count) caractères"
                        + (keepsOldNotes ? " ; les anciennes sont gardées au journal du projet)" : ")"))
        }
        let contacts = ContactStore(projects.database)
        let allLinks = try contacts.links().filter { $0.projectID == project.id }
        let links = allLinks.filter { !$0.excluded }
        var toLink: ContactRow?
        if let contact = Self.given(contact) {
            let row = try findContact(contact)
            // Taken out of the project, it stays out: only Paul puts it back (review of 16/11).
            if allLinks.contains(where: { $0.contactID == row.id && $0.excluded }) {
                throw ToolError("\(Self.contactLabel(row)) a été retiré de « \(project.name) » : seul Paul l'y remet, depuis la page du projet.")
            }
            let linked = links.contains { $0.contactID == row.id }
            if !linked { toLink = row }
            said.append("contact \(Self.contactLabel(row)) \(linked ? "déjà lié" : "lié")")
        }
        var toRemove: ContactRow?
        if let removeContact = Self.given(removeContact) {
            let row = try findContact(removeContact)
            guard links.contains(where: { $0.contactID == row.id }) else {
                throw ToolError("\(Self.contactLabel(row)) n'est pas lié à « \(project.name) » : rien à retirer.")
            }
            toRemove = row
            said.append("contact \(Self.contactLabel(row)) retiré")
        }
        guard !said.isEmpty else {
            throw ToolError("Rien à changer : donne « statut », « echeance », « tache », « client », « notes », « contact » ou « retirer_contact ».")
        }
        if edited.dueDate != project.dueDate || edited.todo != project.todo || edited.client != project.client {
            try projects.saveChanges(from: project, to: edited, at: now())
        }
        if let newNotes {
            if keepsOldNotes {
                try projects.addJournal(ProjectJournalRow(projectID: project.id, date: now(), title: "Notes avant leur remplacement par un agent",
                                                          body: project.notes, createdAt: now()))
            }
            // Written by a session, as `note` writes: not a change of Paul's (`lastEditedAt` stays).
            var notesOnly = project
            notesOnly.notes = newNotes
            notesOnly.updatedAt = now()
            try projects.saveNotes(notesOnly)
        }
        if let toLink { try contacts.include(contactID: toLink.id, projectID: project.id, at: now()) }
        if let toRemove { try contacts.exclude(contactID: toRemove.id, projectID: project.id, at: now()) }
        // The project's page, open in the app, hears of its contacts through its row (review of 16/11).
        if toLink != nil || toRemove != nil { try projects.touch(project.id, at: now()) }
        if let newStatus, newStatus != project.status {
            try projects.move(project.id, to: newStatus, before: nil, at: now())
        }
        return "« \(project.name) » : " + said.joined(separator: ", ") + "."
    }

    /// Paul's 7 (16/11): a new project, when Paul asks, at the bottom of its column as the board's « + » makes it,
    /// with what was given. Its name must be new (case and accents ignored); everything is read before it is made.
    public func create(name: String, status: String?, client: String?, due: String?, folder: String?) throws -> String {
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
        let name = try Self.required(name, "nom", "le nom du nouveau projet")
        if let same = try projects.projects().first(where: { Self.fold($0.name) == Self.fold(name) }) {
            throw ToolError("Un projet s'appelle déjà « \(same.name) » : choisis un autre nom, ou change celui-ci avec `projet`.")
        }
        let column = try Self.given(status).map(Self.status) ?? Self.newProjectStatus
        let deadline = try Self.given(due).flatMap { try dueDate($0) }
        let clientName = client.flatMap(Self.clientName)
        let codeFolder = try Self.given(folder).map(newCodeFolder)
        let added = try projects.addProject(name: name, status: column, at: now())
        var filled = added
        filled.client = clientName
        filled.dueDate = deadline
        filled.codeFolder = codeFolder
        filled.createdOn = added.createdAt
        try projects.saveChanges(from: added, to: filled, at: now())
        var said = [column.label]
        if let clientName { said.append("client « \(clientName) »") }
        if let deadline { said.append("échéance \(day(deadline))") }
        if let codeFolder { said.append("dossier \(codeFolder)") }
        return "Projet « \(name) » créé : " + said.joined(separator: ", ") + "."
            + (codeFolder == nil ? "" : " Une session ouverte dans ce dossier travaillera sur ce projet.")
    }

    /// A new project's code folder: a folder of the Mac, its own. Never the home folder or one above it (every session
    /// would take the project for its own), never one that holds another project's folder (review of 16/11), never an
    /// app or a package (audit of 19/11).
    func newCodeFolder(_ folder: String) throws -> String {
        let path = Self.normalized(folder)
        guard path.hasPrefix("/") else { throw ToolError("« dossier » attend le chemin complet d'un dossier du Mac (/Users/…), pas « \(folder) ».") }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
            throw ToolError("« dossier » : \(path) n'est pas un dossier du Mac.")
        }
        // An app is a folder too, which « Ouvrir le dossier de code » would launch (audit of 19/11).
        if (try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
            throw ToolError("« dossier » : \(path) est une app ou un paquet, pas un dossier de code. Rien n'a été créé.")
        }
        let home = Self.normalized(self.home.path(percentEncoded: false))
        guard path != "/", !(home + "/").hasPrefix(path + "/") else {
            throw ToolError("« dossier » : \(path) est trop large (le dossier de départ ou au-dessus) : donne le dossier de code du projet lui-même.")
        }
        let holder = try projects.projects().first { project in
            guard let other = Self.folderPath(project.codeFolder).map(Self.normalized) else { return false }
            return other == path || other.hasPrefix(path + "/")
        }
        if let holder { throw ToolError("« dossier » : \(path) contient déjà le dossier du projet « \(holder.name) » : donne un dossier à lui.") }
        return path
    }

    /// A contact of the base, by its address (« Nom <adresse> » too) or its name, case and accents ignored; a piece
    /// of one name will do. Never created here: an unknown one is refused.
    func findContact(_ text: String) throws -> ContactRow {
        var key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = key.lastIndex(of: "<"), let close = key.lastIndex(of: ">"), open < close {
            key = String(key[key.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        }
        let store = ContactStore(projects.database)
        if key.contains("@") {
            guard let found = try store.contact(email: key), found.deletedAt == nil else {
                throw ToolError("Aucun contact n'a l'adresse « \(key) » : Paul l'ajoute depuis un mail ou un rendez-vous.")
            }
            return found
        }
        let all = try store.contacts()
        let exact = all.filter { Self.fold($0.name) == Self.fold(key) }
        let matches = exact.isEmpty ? all.filter { Self.contains($0.name, key) } : exact
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw ToolError("Aucun contact ne s'appelle « \(key) » : donne son adresse, ou cherche-le avec `contacts`.") }
        throw ToolError("« \(key) » désigne plusieurs contacts : " + matches.map(Self.contactLabel).joined(separator: ", ") + ". Donne son adresse.")
    }

    /// « Jules Roy (jules@exemple.fr) ».
    static func contactLabel(_ contact: ContactRow) -> String {
        contact.email.map { "\(contact.name) (\($0))" } ?? contact.name
    }

    /// A text argument, `nil` when absent or blank.
    static func given(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func status(_ text: String) throws -> ProjectStatus {
        guard let value = ProjectStatus.allCases.first(where: { fold($0.rawValue) == fold(text) }) else {
            throw ToolError("Statut inconnu « \(text) » : " + ProjectStatus.allCases.map(\.rawValue).joined(separator: ", ") + ".")
        }
        return value
    }

    /// « AAAA-MM-JJ » as the start of that day, or `nil` for « aucune ».
    func dueDate(_ text: String) throws -> Date? {
        if ["aucune", "aucun", "sans", "rien"].contains(Self.fold(text)) { return nil }
        guard let date = dayStart(text) else { throw ToolError("Échéance illisible « \(text) » : AAAA-MM-JJ, ou « aucune ».") }
        return date
    }

    /// The client's name, `nil` for empty or « aucun ».
    static func clientName(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || ["aucun", "aucune"].contains(fold(text)) ? nil : text
    }

    /// An open action reworded, or removed (`remove`), by its number in `actions`.
    public func editAction(_ which: String?, number: Int, text: String, remove: Bool) throws -> String {
        // One call, one change: undone together (step 3 of Colin, 18/11).
        let projects = self.projects.batch()
        let project = try resolve(which)
        let open = try openActions(project)
        guard open.indices.contains(number - 1) else {
            throw ToolError("L'action \(number) n'existe pas : « \(project.name) » a \(open.count) action\(open.count > 1 ? "s" : "") ouverte\(open.count > 1 ? "s" : ""). Voir `actions`.")
        }
        var action = open[number - 1]
        if remove {
            try projects.deleteAction(id: action.id)
            return "Action retirée de « \(project.name) » : \(action.text)"
        }
        action.text = try Self.required(text, "texte", "le nouveau texte de l'action")
        action.updatedAt = now()
        try projects.saveAction(action)
        return "Action \(number) de « \(project.name) » : \(action.text)"
    }

    /// « 2026-12-04 » as the start of that day, here.
    func dayStart(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: text)
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
        guard let project = try project(forFolder: workingDirectory) else {
            throw ToolError("Le dossier \(workingDirectory) n'est lié à aucun projet : précise « projet » (outil `projets`).")
        }
        return project
    }

    /// The project whose code folder holds this one, the closest; none when no project's does.
    func project(forFolder path: String) throws -> ProjectRow? {
        let here = Self.normalized(path)
        let linked = try projects.projects().compactMap { project -> (ProjectRow, String)? in
            guard let folder = Self.folderPath(project.codeFolder).map(Self.normalized) else { return nil }
            return here == folder || here.hasPrefix(folder + "/") ? (project, folder) : nil
        }
        return linked.max(by: { $0.1.count < $1.1.count })?.0
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
