import Foundation

/// The tools of Colin's profile (`polhub mcp --colin`): what he reads, and the drafts (step 2, 18/11); the kanban when
/// the user asks — status, deadline, task, actions, journal (step 3, 18/11). The same list says what the server
/// offers and what Claude Code may run.
public enum ColinTool: String, CaseIterable, Sendable {
    case projets, contexte, actions, reunions, reunion, chercher, mails, mail, agenda, contacts, brouillon
    case projet, action, fait, journal

    /// A change of a project: written in the project named, and only if what was read allows it.
    public var changesAProject: Bool { [.projet, .action, .fait, .journal].contains(self) }

    /// The arguments a change of a project may carry: never the notes, the client, the contacts, nor an action removed.
    public var projectFields: Set<String> {
        switch self {
        case .projet: ["projet", "statut", "echeance", "tache"]
        case .action: ["projet", "texte", "numero"]
        case .fait: ["projet", "numeros"]
        case .journal: ["projet", "titre", "details"]
        default: []
        }
    }

    /// As Claude Code names a tool of the server `polhub`.
    public var allowedName: String { "mcp__polhub__\(rawValue)" }

    public static var allowed: [String] { allCases.map(\.allowedName) }

    /// How the server begins a refusal of its lock (what Colin read of a third party keeps his drafts on that thread
    /// or project): the app reads it to start the next question on a fresh context.
    public static let lockMark = "Verrou de Colin"
}
