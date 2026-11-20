import Persistence
import HubDesign
import SwiftUI

/// The words of Réglages › Mails (lot 7, 19/11): one line of help under each setting that needs one, the long texts
/// behind « ⓘ ».
enum MailSettingsText {
    // « ligne » is the code's word (lot 10, 20/11).
    static let densityHelp = "« Par défaut » montre les pièces jointes ; « Compacte » resserre la liste."
    static let imagesHelp = "Une image chargée dit à l'expéditeur que tu as ouvert son mail."
    static let imagesDetail = "Une image distante qui se charge montre à son expéditeur l'adresse IP de ton Mac et l'heure d'ouverture. « Pour les expéditeurs connus » : tes contacts, les personnes à qui tu as écrit, et ceux pour qui tu as dit « Toujours », quand Gmail confirme que le mail vient bien d'eux. Les images jointes au mail s'affichent toujours."
    static let undoHelp = "Le temps pendant lequel « Annuler » rappelle un mail, après « Envoyer »."
    /// Security audit of 19/11, M6: the scope is kept in the app's preferences, which any session with a terminal can write.
    static let agentsHelp = "Une préférence, pas une barrière : une session qui a un terminal peut la changer."
    /// Colin is « en marche », never « allumé »; no word of the code (« la copie », the tools' names) (lot 10, 20/11).
    static let agentsDetail = "Tes agents Claude Code, et Colin quand il est en marche, lisent tes mails par Polhub, hors spam et corbeille. Ce qu'ils lisent part chez Anthropic. Ils ne peuvent rien envoyer : leurs brouillons t'attendent ici, marqués « préparé par un agent »."

    /// How Polhub sorts the mails, beside what it remembered of Paul's choices: the « ⓘ » of « Ce que Polhub a retenu ».
    static var rules: String {
        "La première règle qui répond l'emporte :\n"
            + MailSortingSections.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            + "\nUne personne ne doit jamais finir cachée dans Automatiques : si ça arrive, clic droit sur le mail › « Ranger dans »."
    }

    /// Every help of the page, for its test.
    static let helps = [densityHelp, imagesHelp, undoHelp, agentsHelp]
}

/// Réglages › Mails (Paul, 15/11: « plus de réglages, des trucs plus fins ») : la liste, la lecture, l'envoi, les agents,
/// et ce que Polhub a retenu. Les choix suivent ceux de Gmail, sous ses noms.
struct MailSettingsPane: View {
    let mails: MailLibrary?
    @AppStorage(Preferences.Key.mailDensity) private var density = MailDensity.defaut.rawValue
    @AppStorage(Preferences.Key.mailDays) private var days = false
    @AppStorage(Preferences.Key.mailImages) private var images = MailImages.connus.rawValue
    @AppStorage(Preferences.Key.mailAfterGesture) private var after = MailAfterGesture.suivant.rawValue
    @AppStorage(Preferences.Key.mailUndoSeconds) private var undo = 10
    @AppStorage(Preferences.Key.mailAgentsScope) private var agents = "tout"

    var body: some View {
        Form {
            Section {
                SettingRow("Densité d'affichage", help: MailSettingsText.densityHelp) {
                    Picker("Densité d'affichage", selection: $density) {
                        ForEach(MailDensity.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                Toggle("Séparer les jours (Aujourd'hui, Hier…)", isOn: $days)
            } header: {
                Text("Liste")
            }
            Section {
                Picker("Après un archivage ou une suppression", selection: $after) {
                    ForEach(MailAfterGesture.allCases) { Text($0.title).tag($0.rawValue) }
                }
                SettingRow("Images distantes", help: MailSettingsText.imagesHelp, detail: MailSettingsText.imagesDetail) {
                    Picker("Images distantes", selection: $images) {
                        ForEach(MailImages.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                }
            } header: {
                Text("Lecture")
            }
            Section {
                SettingRow("Délai d'annulation de l'envoi", help: MailSettingsText.undoHelp) {
                    Picker("Délai d'annulation de l'envoi", selection: $undo) {
                        // Accorded by `Words` (lot 10, 20/11).
                        ForEach(Preferences.Default.mailUndoChoices, id: \.self) { Text(Words.count($0, "seconde")).tag($0) }
                    }
                }
            } header: {
                Text("Envoi")
            }
            // What leaves the Mac, before the list of senders that grows (lot 7, 19/11).
            Section {
                SettingRow("Ce que lisent tes agents", help: MailSettingsText.agentsHelp, detail: MailSettingsText.agentsDetail) {
                    Picker("Ce que lisent tes agents", selection: $agents) {
                        Text("Tous les mails").tag("tout")
                        Text("Les mails de tes projets").tag("projets")
                    }
                }
            } header: {
                Text("Agents")
            }
            if let mails { MailSortingSections(mails: mails) }
        }
        .settingsForm()
    }
}

/// Ce que Polhub a retenu de tes choix, expéditeur par expéditeur : chacun s'oublie d'un clic (Paul, 15/11 : « voir un peu
/// comment c'est trié ») ; comment il trie, derrière « ⓘ » (lot 7, 19/11 : plus une section de documentation).
struct MailSortingSections: View {
    @ObservedObject var mails: MailLibrary

    /// Where a mail goes, by the mails' folders (lot 7, 19/11: the tabs « Personnes » and « Notifications » are gone).
    static let steps = [
        "Ton choix pour ce fil, puis pour son expéditeur (clic droit › « Ranger dans »).",
        "Un fil où tu as écrit, un de tes contacts ou quelqu'un à qui tu as écrit : la Boîte de réception. Un contact d'un seul projet range le fil dans ce projet.",
        // « newsletter », never « lettre » (lot 10, 20/11).
        "Un mail automatique : Automatiques, avec sa case, Newsletters (une newsletter, une promotion), Paiements (un reçu, une facture) ou Services (le reste).",
        "Sinon, la catégorie de Gmail : Notifications, Promotions et Réseaux sociaux vont dans Automatiques ; le reste dans la Boîte de réception.",
    ]

    /// The folder a sender's mails always go to.
    static func place(_ tab: MailTab) -> String {
        switch tab {
        case .personnes: "la \(MailFolder.inbox.title)"
        case .notifications: MailFolder.notifications.title
        }
    }

    var body: some View {
        Section {
            let remembered = mails.senders.values.filter { $0.tab != nil || $0.filing != nil || $0.images }.sorted { $0.address < $1.address }
            if remembered.isEmpty {
                Text("Rien pour l'instant. Quand tu ranges un mail ou que tu affiches toujours ses images, Polhub retient son expéditeur ici.")
                    .foregroundStyle(.secondary)
            }
            ForEach(remembered, id: \.address) { row in
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.address).lineLimit(1)
                        Text(what(row)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Space.m)
                    Button("Oublier") { mails.forget(row.address) }
                        // « Verbe + objet : conséquence », 60 characters at most (lot 10, 20/11).
                        .help(Words.help("Oublier cet expéditeur", detail: "ses mails suivent les règles"))
                }
            }
        } header: {
            HStack(spacing: Space.xs) {
                Text("Ce que Polhub a retenu")
                InfoBubble(MailSettingsText.rules)
            }
        }
    }

    private func what(_ row: MailSenderRow) -> String {
        var parts: [String] = []
        if let tab = row.tab.flatMap(MailTab.init(rawValue:)) { parts.append("toujours dans \(Self.place(tab))") }
        if let filing = row.filing.flatMap(MailFiling.init(rawValue:)) {
            switch filing {
            case .project(let id): parts.append("rangé dans « \(mails.project(id)?.name ?? "un projet") »")
            case .none: parts.append("sans case")
            default: parts.append("rangé dans \(filing.title ?? "")")
            }
        }
        if row.images { parts.append("images toujours affichées") }
        return parts.joined(separator: " · ")
    }
}
