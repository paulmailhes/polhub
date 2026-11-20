import Foundation

/// The conversations of Claude Code, for Colin (20/11): the list, and one conversation page by page, read only.
extension MCPServer {
    static var conversationTools: [[String: Any]] { [
        [
            "name": "conversations", "title": "Les conversations de Claude Code",
            "description": "Les conversations de Claude Code sur ce Mac, la plus récente d'abord : identifiant, date, dossier, titre, dernier message.",
            "inputSchema": ["type": "object", "properties": [
                "projet": ["type": "string", "description": "Seulement celles du dossier de code de ce projet (son nom)."],
                "texte": ["type": "string", "description": "Seulement celles dont le titre, le dossier ou le dernier message contiennent ces mots."],
                "limite": ["type": "integer", "description": "Nombre maximal de conversations (20 par défaut, 100 au plus)."],
            ]],
            "annotations": ["readOnlyHint": true],
        ],
        [
            "name": "conversation", "title": "Une conversation de Claude Code",
            "description": "Les messages de l'utilisateur et les réponses de Claude d'une conversation, sans les outils. Sans `page` : la plus récente.",
            "inputSchema": ["type": "object", "required": ["quelle"], "properties": [
                "quelle": ["type": "string", "description": "L'identifiant donné par `conversations` (entre crochets), ou des mots de son titre."],
                "page": ["type": "integer", "description": "La page, de 1 (le début) à la dernière (par défaut)."],
            ]],
            "annotations": ["readOnlyHint": true],
        ],
    ] }

    /// `nil` for another tool.
    func callConversation(_ name: String, _ arguments: [String: Any]) throws -> String? {
        guard name == "conversations" || name == "conversation" else { return nil }
        guard let conversations else { throw ToolError("Les conversations de Claude Code ne se lisent pas ici.") }
        if name == "conversation" {
            guard let which = Self.text(arguments["quelle"]) else {
                throw ToolError("Il manque « quelle » : l'identifiant d'une conversation (outil `conversations`) ou des mots de son titre.")
            }
            return try conversations.conversation(which, page: (arguments["page"] as? Int) ?? Int(Self.text(arguments["page"]) ?? ""))
        }
        var folder: String?
        if let projectName = Self.text(arguments["projet"]) {
            guard let desk else { throw ToolError("Les projets ne se lisent pas ici.") }
            let project = try desk.resolve(projectName)
            guard let linked = ProjectDesk.folderPath(project.codeFolder) else {
                throw ToolError("Le projet « \(project.name) » n'est lié à aucun dossier de code : cherche ses conversations par `texte`.")
            }
            folder = linked
        }
        return try conversations.list(folder: folder, text: Self.text(arguments["texte"]), limit: arguments["limite"] as? Int ?? 20)
    }

    /// What a conversation put before Colin: its project, when its folder is the project's code folder; else wide.
    func conversationScope(_ which: String?) throws -> ColinScope {
        guard let which, let conversations, let desk, let folder = try conversations.folder(of: which),
              let project = try desk.project(forFolder: folder) else { return .wide }
        return .project(project.id)
    }
}
