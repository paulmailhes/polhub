import Foundation
import MailFormat
import Persistence

/// Paul, 17/11: « il me le recrée à chaque fois ». An agent sees the drafts the agents prepared, changes one by its
/// identifier instead of dropping another, or deletes it, when Paul asks. Never a draft Paul wrote. A drop still
/// waiting for the app changes in place; a draft already in Polhub gets a request the app applies (this helper has
/// no network, and only the app speaks to Gmail).
extension MailDesk {
    /// What an identifier names: a drop the app has not taken yet, or a draft in Polhub.
    enum Changeable {
        case waiting(MailAgentDraftRow)
        case draft(MailDraftRow)

        var id: String {
            switch self {
            case .waiting(let drop): drop.id
            case .draft(let draft): draft.id
            }
        }

        var subject: String {
            switch self {
            case .waiting(let drop): drop.subject
            case .draft(let draft): draft.subject
            }
        }
    }

    func requireChanges() throws {
        guard try store.acceptsAgentDrafts(), try store.agentDraftsTakeFiles(), try store.agentDraftsChange() else {
            throw ToolError("La base de Polhub ne connaît pas encore ce geste : la dernière version de Polhub doit être ouverte une fois.")
        }
    }

    // MARK: - Reading

    /// The drafts the agents prepared, the last changed first, with their text and their identifier.
    public func drafts() throws -> String {
        try requireChanges()
        let rules = try store.filingRules()
        let readable = Set(try readable(rules).map(\.id))
        let waiting = try store.agentDrafts().filter { $0.replaces == nil }
        let kept = try store.drafts().filter { $0.origin == .agent && ($0.threadKey.map(readable.contains) ?? true) }
        var lines = ["# Les brouillons préparés par un agent (\(waiting.count + kept.count))"]
        guard !waiting.isEmpty || !kept.isEmpty else {
            return (lines + ["Aucun. Les brouillons écrits par Paul ne se lisent ni ne se changent ici."]).joined(separator: "\n")
        }
        let requests = try store.agentDrafts().compactMap(\.replaces)
        for draft in kept.prefix(30) {
            var parts = ["« \(draft.subject.isEmpty ? "(sans objet)" : Self.line(draft.subject)) »", kind(draft.mode, threadKey: draft.threadKey),
                         "boîte \(draft.account)", "modifié le \(moment(draft.updatedAt))"]
            if draft.retouchedByPaul { parts.append("retouché par Paul : repars de ce texte") }
            if requests.contains(draft.id) { parts.append("une modification demandée attend que Polhub l'applique") }
            lines.append("- [\(draft.id)] " + parts.joined(separator: " · "))
            // Formatted: given as the little markdown, to give back with « format » markdown and keep its formatting.
            let text = draft.bodyHTML.map(MailRichText.markdown) ?? draft.body
            lines += details(to: draft.to, cc: draft.cc, body: text, files: draft.files.map(\.filename), markdown: draft.bodyHTML != nil)
            seen.read(draft.id, at: draft.updatedAt)
        }
        for drop in waiting.prefix(30) {
            let parts = ["« \(drop.subject.isEmpty ? "(objet du fil)" : Self.line(drop.subject)) »", kind(drop.mode, threadKey: drop.threadKey),
                         drop.account.map { "boîte \($0)" } ?? "", "déposé le \(moment(drop.createdAt))",
                         "pas encore dans Polhub : il y entre à son ouverture"].filter { !$0.isEmpty }
            lines.append("- [\(drop.id)] " + parts.joined(separator: " · "))
            lines += details(to: drop.to, cc: drop.cc, body: drop.body, files: drop.files.map(\.filename), markdown: drop.format == .markdown)
        }
        lines.append("")
        lines.append("Pour en changer un : `brouillon` avec son « identifiant » et ce qui change (« texte » en entier, « objet », « a », « cc », "
                     + "« fichiers » qui s'ajoutent). Repars du texte ci-dessus : il garde ce que Paul y a retouché. Pour le supprimer : « identifiant » "
                     + "et « supprimer ». Les brouillons écrits par Paul ne se lisent ni ne se changent ici.")
        return lines.joined(separator: "\n")
    }

    private func kind(_ mode: MailDraftRow.Mode, threadKey: String?) -> String {
        let thread = threadKey.flatMap { try? store.thread($0) }
        switch mode {
        case .reply: return "réponse sous le fil « \(Self.line(thread?.subject ?? "?")) » [\(thread?.threadID ?? "?")]"
        case .replyAll: return "réponse à tous sous le fil « \(Self.line(thread?.subject ?? "?")) » [\(thread?.threadID ?? "?")]"
        case .forward: return "transfert"
        default: return "nouveau mail"
        }
    }

    private func details(to: [MailAddress], cc: [MailAddress], body: String, files: [String], markdown: Bool) -> [String] {
        var lines: [String] = []
        if !to.isEmpty { lines.append("  À : " + to.map(address).joined(separator: ", ")) }
        if !cc.isEmpty { lines.append("  Cc : " + cc.map(address).joined(separator: ", ")) }
        lines.append(markdown ? "  Texte, mis en forme (à renvoyer avec « format » markdown) :" : "  Texte :")
        let text = HTMLText.clean(body)
        let shown = text.count > 4_000 ? String(text.prefix(4_000)) + " […]" : text
        lines += shown.split(separator: "\n", omittingEmptySubsequences: false).map { "  > " + $0 }
        if !files.isEmpty { lines.append("  Fichiers : " + files.map { "« \(Self.line($0)) »" }.joined(separator: ", ")) }
        return lines
    }

    // MARK: - Changing

    /// The draft named: a drop waiting, or a draft in Polhub the agents prepared, by its identifier or its beginning
    /// (8 characters at least). A draft Paul wrote is refused, said as such.
    func changeable(_ which: String) throws -> Changeable {
        let key = which.trimmingCharacters(in: CharacterSet(charactersIn: "[] ").union(.whitespacesAndNewlines)).lowercased()
        guard !key.isEmpty else { throw ToolError("Il manque « identifiant » : celui d'un brouillon (outil `mails` avec « brouillons »).") }
        let waiting = try store.agentDrafts().filter { $0.replaces == nil }
        let drafts = try store.drafts()
        if let drop = waiting.first(where: { $0.id == key }) { return .waiting(drop) }
        if let draft = drafts.first(where: { $0.id == key }) { return try allowed(draft) }
        if key.count >= 8 {
            let started = waiting.filter { $0.id.hasPrefix(key) }.map(Changeable.waiting)
                + drafts.filter { $0.origin == .agent && $0.id.hasPrefix(key) }.map(Changeable.draft)
            if started.count == 1, let only = started.first {
                if case .draft(let draft) = only { return try allowed(draft) }
                return only
            }
        }
        throw ToolError("Aucun brouillon préparé par un agent ne répond à « \(key) ». La liste : `mails` avec « brouillons ».")
    }

    private func allowed(_ draft: MailDraftRow) throws -> Changeable {
        guard draft.origin == .agent else {
            throw ToolError("« \(Self.line(draft.subject)) » est un brouillon écrit par Paul : un agent ne le change ni ne le supprime. "
                            + "Dis à Paul ce qu'il faudrait changer, ou dépose un autre brouillon s'il le demande.")
        }
        // Retouched by Paul since this session read it: reread first, never write over his changes from memory.
        if draft.retouchedByPaul, seen.version(of: draft.id) != draft.updatedAt {
            throw ToolError("Paul a retouché « \(Self.line(draft.subject)) » depuis ta dernière lecture : relis-le avec `mails` et « brouillons », "
                            + "puis repars de son texte pour garder ses changements. Rien n'a changé.")
        }
        if let key = draft.threadKey {
            let rules = try store.filingRules()
            guard try readable(rules).contains(where: { $0.id == key }) else {
                throw ToolError("Aucun brouillon préparé par un agent ne répond à « \(draft.id) » parmi ceux que Paul laisse lire.")
            }
        }
        return .draft(draft)
    }

    /// Changes what is given of a draft the agents prepared: its text (and its format), for a new mail its subject
    /// and its people, its files (they replace those joined). The rest stays.
    public func change(_ which: String, text: String, subject: String?, to: [String], cc: [String], format: MailAgentDraftRow.Format?,
                       joining paths: [String] = []) throws -> String {
        try requireChanges()
        let body = HTMLText.clean(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.count <= Self.maximumText else { throw ToolError("Le texte dépasse \(Self.maximumText) caractères.") }
        let people = try Self.addresses(to, "a"), copies = try Self.addresses(cc, "cc")
        let title = subject.map(Self.line) ?? ""
        guard !body.isEmpty || !title.isEmpty || !people.isEmpty || !copies.isEmpty || !paths.isEmpty else {
            throw ToolError("Rien à changer : donne « texte », « objet », « a », « cc » ou « fichiers ». Pour le supprimer : « supprimer ».")
        }
        let chosen = try joinable(paths)
        let target = try changeable(which)
        var notes: [String] = []
        let isReply: Bool
        switch target {
        case .waiting(let drop): isReply = drop.mode != .new
        case .draft(let draft): isReply = draft.mode != .new
        }
        if isReply, !title.isEmpty || !people.isEmpty || !copies.isEmpty {
            notes.append("Pour une réponse, l'objet et les destinataires viennent du fil : « objet », « a » et « cc » sont ignorés.")
        }
        if case .waiting(var drop) = target {
            var added: [MailDraftFile] = []
            if !body.isEmpty {
                drop.body = body
                drop.format = format ?? drop.format
            }
            if !isReply {
                if !title.isEmpty { drop.subject = title }
                if !people.isEmpty { drop.to = people }
                if !copies.isEmpty { drop.cc = copies }
            }
            if !chosen.isEmpty {
                let names = Set(chosen.map(\.name))
                guard drop.files.filter({ !names.contains($0.filename) }).count + chosen.count <= Self.maximumFiles else {
                    throw ToolError("\(Self.maximumFiles) fichiers au plus par brouillon. Rien n'a changé.")
                }
                for name in names { try? FileManager.default.removeItem(at: files.agentFolder(id: drop.id).appending(path: name)) }
                added = try stage(chosen, for: drop.id)
                drop.files = drop.files.filter { !names.contains($0.filename) } + added
            }
            if try store.updateDrop(drop) {
                return answer("modifié", target, notes: notes, files: added)
            }
            // Taken by the app meanwhile: it is a draft in Polhub now, with the same identifier.
            return try change(drop.id, text: text, subject: subject, to: to, cc: cc, format: format, joining: paths)
        }
        guard case .draft(let draft) = target else { return "" }
        var request = MailAgentDraftRow(mode: draft.mode, account: draft.account, threadKey: draft.threadKey,
                                        to: isReply ? [] : people, cc: isReply ? [] : copies, subject: isReply ? "" : title, body: body,
                                        createdAt: now(), format: format ?? (draft.bodyHTML != nil ? .markdown : .plain), replaces: draft.id,
                                        basedOn: draft.updatedAt)
        request.files = try stage(chosen, for: request.id)
        do {
            try store.drop(request)
        } catch {
            try? FileManager.default.removeItem(at: files.agentFolder(id: request.id))
            throw error
        }
        return answer("modifié", target, notes: notes, files: request.files)
    }

    /// Deletes a draft the agents prepared: a drop waiting goes at once; a draft in Polhub, by the app (and from Gmail).
    public func discard(_ which: String) throws -> String {
        try requireChanges()
        let target = try changeable(which)
        switch target {
        case .waiting(let drop):
            if try store.agentDraft(drop.id) != nil {
                try store.discardAgentDraft(drop.id)
                try? FileManager.default.removeItem(at: files.agentFolder(id: drop.id))
                if try store.draft(drop.id) == nil { return answer("supprimé", target, notes: [], files: []) }
            }
            return try discard(drop.id)
        case .draft(let draft):
            try store.drop(MailAgentDraftRow(mode: draft.mode, account: draft.account, threadKey: draft.threadKey, body: "", createdAt: now(),
                                             replaces: draft.id, discard: true, basedOn: draft.updatedAt))
            return answer("supprimé", target, notes: [], files: [])
        }
    }

    private func answer(_ done: String, _ target: Changeable, notes: [String], files: [MailDraftFile]) -> String {
        let name = target.subject.isEmpty ? "le brouillon" : "« \(Self.line(target.subject)) »"
        let deleted = done == "supprimé"
        var text: String
        switch target {
        case .waiting:
            text = deleted ? "Brouillon \(name) supprimé (identifiant \(target.id)) : il n'était pas encore entré dans Polhub. "
                : "Brouillon \(name) modifié (identifiant \(target.id)) : Polhub le prendra ainsi à son ouverture. "
        case .draft:
            text = "Demande déposée : Polhub \(deleted ? "supprime" : "modifie") \(name) (identifiant \(target.id)) dès qu'il est ouvert"
                + (deleted ? ", dans Gmail aussi. " : ". ")
                + "Il refuse, et le dit à Paul, si le brouillon est programmé, en train de partir ou retouché par Paul entre-temps. "
            if !deleted { text += "La version de l'agent reste dans Polhub, hors de Gmail, jusqu'à ce que Paul l'ait vue. " }
        }
        if !files.isEmpty {
            text += "Fichiers joints en plus : " + files.map { "« \($0.filename) » (\(Self.size($0.size)))" }.joined(separator: ", ") + ". "
        }
        text += notes.map { $0 + " " }.joined()
        return text + (deleted ? "" : "Paul le relit et l'envoie lui-même : aucun outil ne peut l'envoyer.")
    }
}
