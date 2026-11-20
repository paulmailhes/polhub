import Foundation

/// Made-up answers, for the iPhone's captures and its demonstration mode: every name and address here is invented.
public enum LinkDemo {
    public static func answer(_ path: String, query: [String: String], now: Date = Date()) -> Data? {
        let calendar = LinkWords.calendar
        func at(_ days: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        let encoder = LinkAPI.encoder
        switch path {
        case LinkAPI.Path.status:
            return try? encoder.encode(LinkStatus(appVersion: "0.52.0", device: "iPhone"))
        case LinkAPI.Path.folders:
            return try? encoder.encode([LinkFolder(id: "inbox", title: "Boîte de réception", unread: 2),
                                        LinkFolder(id: "notifications", title: "Automatiques", unread: 5),
                                        LinkFolder(id: "sent", title: "Envoyés", unread: 0),
                                        LinkFolder(id: "all", title: "Tous les messages", unread: 0)])
        case LinkAPI.Path.threads:
            return try? encoder.encode(threads(now: now, at: at))
        case LinkAPI.Path.thread:
            let thread = threads(now: now, at: at).first { $0.id == query["fil"] } ?? threads(now: now, at: at)[0]
            let dark = query["sombre"] == "1"
            let camille = LinkPerson(name: "Camille Martin", email: "camille.martin@exemple-studio.fr")
            let me = LinkPerson(name: "Moi", email: "moi@exemple.fr")
            return try? encoder.encode(LinkThreadDetail(thread: thread, messages: [
                LinkMessage(id: "m1", from: camille, to: [me], cc: [], date: at(-1, 17, 20),
                            html: page("Bonjour,<br><br>Voici la deuxième version de la maquette, avec la page contact revue.<br><br>Camille", dark: dark),
                            files: [LinkFile(id: "2", name: "maquette-v2.pdf", mimeType: "application/pdf", size: 1_240_000)], authenticated: true),
                LinkMessage(id: "m2", from: me, to: [camille], cc: [], date: at(-1, 18, 2),
                            html: page("Merci, je regarde ça demain matin.", dark: dark), files: [], authenticated: true),
                LinkMessage(id: "m3", from: camille, to: [me], cc: [], date: at(0, 8, 31),
                            html: page("Parfait. J'ai aussi corrigé la page contact, dis-moi si le formulaire te convient.", dark: dark),
                            files: [], authenticated: true),
            ]))
        case LinkAPI.Path.events:
            return try? encoder.encode([
                LinkEvent(id: "e1", title: "Point Studio Nord", start: at(0, 9, 30), end: at(0, 10), allDay: false, account: "moi@exemple.fr",
                          color: "#3B82F6", meet: URL(string: "https://meet.google.com/abc-defg-hij"), location: nil, project: "Studio Nord"),
                LinkEvent(id: "e2", title: "Revue de maquettes", start: at(0, 14), end: at(0, 15), allDay: false, account: "moi@exemple.fr",
                          color: "#3B82F6", meet: nil, location: "Atelier", project: "Site vitrine"),
                LinkEvent(id: "e3", title: "Déjeuner avec Jules", start: at(1, 12, 30), end: at(1, 14), allDay: false, account: "perso@exemple.fr",
                          color: "#22A06B", meet: nil, location: "Le Comptoir", project: nil),
                LinkEvent(id: "e4", title: "Livraison Maison Leroy", start: at(2, 0), end: at(3, 0), allDay: true, account: "moi@exemple.fr",
                          color: "#3B82F6", meet: nil, location: nil, project: "Maison Leroy"),
            ])
        case LinkAPI.Path.projects:
            return try? encoder.encode(projects(at: at))
        case LinkAPI.Path.project:
            let project = projects(at: at).first { $0.id.uuidString == query["id"] } ?? projects(at: at)[0]
            return try? encoder.encode(LinkProjectDetail(project: project, notes: "Refonte du site : six pages, livraison avant la fin du mois.",
                actions: [LinkAction(id: UUID(), text: "Envoyer la maquette v2", done: true, due: nil),
                          LinkAction(id: UUID(), text: "Valider la page contact avec Camille", done: false, due: at(1, 0, 0))],
                journal: [LinkJournalEntry(id: UUID(), date: at(-1, 18, 0), title: "Maquette v2 envoyée", text: "")],
                events: []))
        case LinkAPI.Path.meetings:
            return try? encoder.encode(meetings(at: at))
        case LinkAPI.Path.meeting:
            let meeting = meetings(at: at).first { $0.id.uuidString == query["id"] } ?? meetings(at: at)[0]
            return try? encoder.encode(LinkMeetingDetail(meeting: meeting,
                summary: "## Décisions\n\n- La maquette v2 est validée.\n- La page contact garde son formulaire.\n\n## Prochaines étapes\n\n- Camille envoie les textes jeudi.",
                turns: [LinkTurn(speaker: "Moi", start: 4, text: "On reprend la maquette ?", doubtful: false),
                        LinkTurn(speaker: "Les autres", start: 9, text: "Oui, j'ai corrigé la page contact.", doubtful: false)]))
        case LinkAPI.Path.reply, LinkAPI.Path.newMail:
            return try? encoder.encode(LinkSending(draftID: "demo", subject: "Maquette v2 du site", at: now.addingTimeInterval(8), leaving: false))
        case LinkAPI.Path.cancel, LinkAPI.Path.sending:
            return try? encoder.encode(LinkSending?.none)
        case LinkAPI.Path.accounts:
            return try? encoder.encode(["moi@exemple.fr", "perso@exemple.fr"])
        case LinkAPI.Path.colin:
            return try? encoder.encode(LinkColin(state: "prêt", answering: false, streaming: "", problem: nil, messages: [
                LinkColinMessage(id: "c1", fromPaul: true, text: "Mets à jour mes projets d'après mes derniers mails.", state: "done", date: at(0, 8, 40)),
                LinkColinMessage(id: "c2", fromPaul: false, text: "C'est fait pour **deux projets** : Site vitrine passe en priorité 2, et Maison Leroy attend le retour d'Anne.", state: "done", date: at(0, 8, 41)),
            ], changes: [
                LinkChange(id: "x1", project: "Site vitrine", at: at(0, 8, 41), note: "Après le mail de Camille, 8:31", created: false,
                           fields: [LinkChangeField(label: "Statut", before: "Priorité 1", after: "Priorité 2")], undone: false),
            ]))
        default:
            return nil
        }
    }

    static func meetings(at: (Int, Int, Int) -> Date) -> [LinkMeeting] {
        [
            LinkMeeting(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, title: "Point Studio Nord", start: at(0, 9, 30), seconds: 1_820,
                        project: "Studio Nord", hasSummary: true),
            LinkMeeting(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, title: "Appel découverte", start: at(-2, 15, 0), seconds: 2_700,
                        project: nil, hasSummary: true),
        ]
    }

    static func threads(now: Date, at: (Int, Int, Int) -> Date) -> [LinkThread] {
        [
            LinkThread(id: "moi@exemple.fr|a", account: "moi@exemple.fr", subject: "Maquette v2 du site", people: "Camille, moi",
                       snippet: "Parfait. J'ai aussi corrigé la page contact.", date: at(0, 8, 31), unread: true, messages: 3, hasFiles: true,
                       project: "Site vitrine"),
            LinkThread(id: "moi@exemple.fr|b", account: "moi@exemple.fr", subject: "Devis signé", people: "Jules Durand",
                       snippet: "Le client a signé, on peut lancer.", date: at(0, 7, 12), unread: true, messages: 1, hasFiles: false,
                       project: "Maison Leroy"),
            LinkThread(id: "moi@exemple.fr|c", account: "moi@exemple.fr", subject: "Photos du week-end", people: "Nina Roche",
                       snippet: "Je t'envoie les photos de dimanche, elles sont superbes.", date: at(-1, 20, 4), unread: false, messages: 2,
                       hasFiles: true, project: nil),
            LinkThread(id: "moi@exemple.fr|d", account: "moi@exemple.fr", subject: "Planning de mars", people: "Jules Durand",
                       snippet: "Voici le planning mis à jour pour mars.", date: at(-3, 10, 0), unread: false, messages: 4, hasFiles: false,
                       project: "Studio Nord"),
        ]
    }

    static func projects(at: (Int, Int, Int) -> Date) -> [LinkProject] {
        [
            LinkProject(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Site vitrine", status: "priorité 2",
                        client: "Atelier Dupont", due: at(4, 0, 0), task: "Valider la page contact", color: "#3B82F6"),
            LinkProject(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Maison Leroy", status: "priorité 1",
                        client: "Leroy & fils", due: at(-6, 0, 0), task: "Attend le retour d'Anne", color: "#F97316"),
            LinkProject(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Studio Nord", status: "en pause",
                        client: nil, due: nil, task: nil, color: "#8B5CF6"),
        ]
    }

    /// A body as the Mac makes them: a whole document, made safe.
    static func page(_ body: String, dark: Bool) -> String {
        let colors = dark ? "background:#1C1C1E;color:#F5F5F7" : "background:#FFFFFF;color:#1D1D1F"
        return "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\">"
            + "<style>body{font:-apple-system-body;margin:0;\(colors)}</style></head><body>\(body)</body></html>"
    }
}
