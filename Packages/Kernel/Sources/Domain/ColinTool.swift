import Foundation

/// The tools of Colin's profile (`polhub mcp --colin`), step 2 (18/11): what he reads, and the drafts. The same list
/// says what the server offers and what Claude Code may run.
public enum ColinTool: String, CaseIterable, Sendable {
    case projets, contexte, actions, reunions, reunion, chercher, mails, mail, agenda, contacts, brouillon

    /// As Claude Code names a tool of the server `polhub`.
    public var allowedName: String { "mcp__polhub__\(rawValue)" }

    public static var allowed: [String] { allCases.map(\.allowedName) }

    /// How the server begins a refusal of its lock (what Colin read of a third party keeps his drafts on that thread
    /// or project): the app reads it to start the next question on a fresh context.
    public static let lockMark = "Verrou de Colin"
}
