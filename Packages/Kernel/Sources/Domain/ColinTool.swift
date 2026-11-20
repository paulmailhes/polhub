import Foundation

/// The tools of Colin's profile (`hub mcp --colin`): what he reads, and the drafts (step 2, 18/11); the kanban when
/// the user asks — status, deadline, task, actions, journal (step 3, 18/11); a new project when he asks (19/11). The same list says what the server
/// offers and what Claude Code may run.
public enum ColinTool: String, CaseIterable, Sendable {
    case projets, contexte, actions, reunions, reunion, chercher, mails, mail, agenda, contacts
    /// The conversations of Claude Code on the Mac, read only (20/11).
    case conversations, conversation
    case brouillon
    case projet, action, fait, journal
    /// A project created when the user asks (19/11).
    case nouveau_projet

    /// A change of a project: written in the project named, and only if what was read allows it.
    public var changesAProject: Bool { [.projet, .action, .fait, .journal].contains(self) }

    /// A project created: written only on a context where nothing of a third party was read (a mail could name it,
    /// and every agent reads the projects' names).
    public var createsAProject: Bool { self == .nouveau_projet }

    /// What it reads may come from a third party: a mail, a meeting, the agenda, a search, a project's texts. Paul's own
    /// data (the projects, their actions, the contacts) and the writes are not (Colin's lock, 18/11).
    public var readsAThirdParty: Bool { ![.projets, .actions, .contacts, .brouillon, .projet, .action, .fait, .journal, .nouveau_projet].contains(self) }

    /// The arguments a change of a project may carry: never the notes, the client, the contacts, nor an action removed.
    public var projectFields: Set<String> {
        switch self {
        case .projet: ["projet", "statut", "echeance", "tache"]
        case .action: ["projet", "texte", "numero"]
        case .fait: ["projet", "numeros"]
        case .journal: ["projet", "titre", "details"]
        case .nouveau_projet: ["nom", "statut", "client", "echeance"]
        default: []
        }
    }

    /// As Claude Code names a tool of the server `hub`.
    public var allowedName: String { "mcp__hub__\(rawValue)" }

    public static var allowed: [String] { allCases.map(\.allowedName) }

    /// How the server begins a refusal of its lock (what Colin read of a third party keeps his drafts on that thread
    /// or project): the app reads it to start the next question on a fresh context.
    public static let lockMark = "Verrou de Colin"
}
