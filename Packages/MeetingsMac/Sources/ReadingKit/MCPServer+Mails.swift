import Foundation
import Persistence

/// The mail tools that write (16/11): `brouillon`'s files and format, and `ranger`. Their names live here once.
extension MCPServer {
    static let fileThreadTool = "ranger"

    static var mailFilingTools: [[String: Any]] { [
        [
            "name": fileThreadTool, "title": "Ranger un fil",
            "description": "Range un fil dans une case, comme le clic de Paul sur sa case, quand Paul le demande : un projet, Perso, Newsletters, Paiements ou Services, ou « aucun » pour lui retirer sa case. Dans Polhub seulement : rien ne change dans Gmail, rien n'est archivé ni supprimé, et les prochains mails de l'expéditeur ne suivent pas. La réponse nomme le fil et sa nouvelle case.",
            "inputSchema": ["type": "object", "required": ["quel", "projet"], "properties": [
                "quel": ["type": "string", "description": "L'identifiant du fil donné par `mails` (entre crochets), ou des mots de son objet."],
                "projet": ["type": "string", "description": "Le nom du projet (outil `projets`, casse et accents ignorés), ou « Perso », « Newsletters », « Paiements », « Services », ou « aucun »."],
            ]],
            "annotations": ["readOnlyHint": false, "destructiveHint": false],
        ],
    ] }

    /// `brouillon`'s two parameters of 16/11, added to its schema in `mailTools`.
    static var draftFileProperties: [String: Any] { [
        "fichiers": ["type": "array", "items": ["type": "string"],
                     "description": "Seulement quand Paul l'a demandé : les fichiers du Mac à joindre, par leur chemin complet (/Users/…). 10 au plus, 25 Mo en tout ; jamais un fichier caché (un worktree de Claude Code, <projet>/.claude/worktrees/…, est permis), un trousseau, un fichier de la Bibliothèque (~/Library, sauf iCloud Drive et les Drive de ~/Library/CloudStorage) ni une pièce jointe gardée par Polhub (Paul la joint depuis le fil). Polhub les copie : le brouillon garde ce qui a été joint."],
        "format": ["type": "string", "enum": ["texte", "markdown"],
                   "description": "« texte » (par défaut) ou « markdown » : **gras**, *italique*, listes « - » et « 1. », liens [texte](https://…), paragraphes. Rien d'autre (ni titre, ni image, ni HTML) : Polhub fait le mail mis en forme lui-même."],
    ] }

    /// `brouillon`'s parameters of 17/11: a draft the agents prepared, changed or deleted by its identifier.
    static var draftChangeProperties: [String: Any] { [
        "identifiant": ["type": "string",
                        "description": "Pour changer un brouillon déjà préparé par un agent, au lieu d'en déposer un autre : son identifiant (donné par cet outil quand il l'a déposé, ou par `mails` avec « brouillons »). Seul ce qui est donné change : « texte » (en entier, et « format »), « objet », « a », « cc » ; les « fichiers » s'ajoutent. Si Paul l'a retouché, relis-le d'abord (`mails` avec « brouillons ») et repars de son texte. Jamais un brouillon écrit par Paul."],
        "supprimer": ["type": "boolean", "description": "Avec « identifiant » : supprime ce brouillon (dans Polhub et dans Gmail), quand Paul le demande."],
    ] }

    /// `brouillon`: a reply or a new mail, its files and its format; or, by its identifier, a change or a deletion.
    func dropDraft(_ arguments: [String: Any], mails: MailDesk) throws -> String {
        func strings(_ key: String) -> [String] {
            if let list = arguments[key] as? [Any] { return list.compactMap { $0 as? String } }
            return (arguments[key] as? String).map { [$0] } ?? []
        }
        let format: MailAgentDraftRow.Format?
        switch Self.text(arguments["format"])?.lowercased() {
        case nil: format = nil
        case "texte", "text", "plain": format = .plain
        case "markdown": format = .markdown
        case let other?: throw ToolError("« format » attend « texte » ou « markdown », pas « \(other) ». Pas de HTML : Polhub fait le mail mis en forme lui-même.")
        }
        if let which = Self.text(arguments["identifiant"]) {
            let ignored = ["quel", "tous", "boite"].filter { arguments[$0] != nil }
            let note = ignored.isEmpty ? "" : " " + ignored.map { "« \($0) »" }.joined(separator: ", ")
                + " ne change\(ignored.count > 1 ? "nt" : "") pas un brouillon existant : ignoré\(ignored.count > 1 ? "s" : "")."
            if arguments["supprimer"] as? Bool == true { return try mails.discard(which) + note }
            return try mails.change(which, text: arguments["texte"] as? String ?? "", subject: Self.text(arguments["objet"]), to: strings("a"),
                                    cc: strings("cc"), format: format, joining: strings("fichiers")) + note
        }
        if arguments["supprimer"] as? Bool == true {
            throw ToolError("Il manque « identifiant » : celui du brouillon à supprimer (outil `mails` avec « brouillons »).")
        }
        return try mails.draft(replyTo: Self.text(arguments["quel"]), all: arguments["tous"] as? Bool ?? false, to: strings("a"), cc: strings("cc"),
                               subject: Self.text(arguments["objet"]), text: arguments["texte"] as? String ?? "", account: Self.text(arguments["boite"]),
                               joining: strings("fichiers"), format: format ?? .plain)
    }

    /// `ranger`: a thread in a case.
    func fileThread(_ arguments: [String: Any], mails: MailDesk) throws -> String {
        guard let which = Self.text(arguments["quel"]) else { throw ToolError("Il manque « quel » : l'identifiant d'un fil (outil `mails`).") }
        guard let place = Self.text(arguments["projet"]) else {
            throw ToolError("Il manque « projet » : le nom d'un projet, ou Perso, Newsletters, Paiements, Services, ou « aucun ».")
        }
        return try mails.fileThread(which, into: place)
    }
}
