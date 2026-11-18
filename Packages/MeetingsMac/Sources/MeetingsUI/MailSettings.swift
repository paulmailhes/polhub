import Persistence
import PolhubDesign
import SwiftUI

/// Réglages › Mails (Paul, 15/11: « plus de réglages, des trucs plus fins ») : la liste, la lecture, l'envoi, le
/// tri des onglets et ce que Polhub a retenu, les agents. Les choix suivent ceux de Gmail, sous ses noms.
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
                Picker("Densité d'affichage", selection: $density) {
                    ForEach(MailDensity.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Séparer les jours (Aujourd'hui, Hier…)", isOn: $days)
            } header: {
                Text("Liste")
            } footer: {
                Text("« Par défaut » montre les pièces jointes sous chaque mail, comme Gmail. « Confortable » les cache, « Compacte » serre aussi les lignes.")
            }
            Section {
                Picker("Après un archivage ou une suppression", selection: $after) {
                    ForEach(MailAfterGesture.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("Images distantes", selection: $images) {
                    ForEach(MailImages.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Lecture")
            } footer: {
                Text("Une image distante qui se charge montre à son expéditeur l'adresse IP de ton Mac et l'heure d'ouverture. « Pour les expéditeurs connus » : tes contacts, les personnes à qui tu as écrit, et ceux pour qui tu as dit « Toujours », quand Gmail confirme que le mail vient bien d'eux. Les images jointes au mail s'affichent toujours.")
            }
            Section {
                Picker("Délai d'annulation de l'envoi", selection: $undo) {
                    ForEach(Preferences.Default.mailUndoChoices, id: \.self) { Text("\($0) secondes").tag($0) }
                }
            } header: {
                Text("Envoi")
            } footer: {
                Text("Le temps pendant lequel « Annuler » rappelle un mail, après « Envoyer ».")
            }
            if let mails { MailSortingSections(mails: mails) }
            Section {
                Picker("Ce que lisent tes agents", selection: $agents) {
                    Text("Tous les mails").tag("tout")
                    Text("Les mails de tes projets").tag("projets")
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Tes agents Claude Code, et Colin quand il est allumé, lisent la copie de tes mails par le serveur de Polhub (outils mails, mail et brouillon), hors spam et corbeille. Ce qu'ils lisent part chez Anthropic. Ils ne peuvent rien envoyer : leurs brouillons t'attendent ici, marqués « préparé par un agent ».")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680)
    }
}

/// Comment Polhub trie les onglets, et ce qu'il a retenu de tes choix, expéditeur par expéditeur : chacun s'oublie
/// d'un clic (Paul, 15/11 : « voir un peu comment c'est trié »).
struct MailSortingSections: View {
    @ObservedObject var mails: MailLibrary

    static let steps = [
        "Ton choix pour ce fil, puis pour son expéditeur (clic droit › « Ranger dans »).",
        "Un fil où tu as écrit, un de tes contacts ou quelqu'un à qui tu as écrit : Personnes. Un contact d'un seul projet range le fil dans ce projet.",
        "Un mail automatique : Notifications, avec sa case, Newsletters (une lettre, une promotion), Paiements (un reçu, une facture) ou Services (le reste).",
        "Sinon, la catégorie de Gmail : Notifications, Promotions et Réseaux sociaux vont dans Notifications ; le reste dans Personnes.",
    ]

    var body: some View {
        Section {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(index + 1).").monospacedDigit().foregroundStyle(.secondary)
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Tri des onglets")
        } footer: {
            Text("La première règle qui répond l'emporte. Une personne ne doit jamais finir cachée dans Notifications : si ça arrive, clic droit sur le mail › « Ranger dans ».")
        }
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
                        .help("Polhub ne retient plus rien de cet expéditeur : ses mails suivent de nouveau les règles")
                }
            }
        } header: {
            Text("Ce que Polhub a retenu")
        }
    }

    private func what(_ row: MailSenderRow) -> String {
        var parts: [String] = []
        if let tab = row.tab.flatMap(MailTab.init(rawValue:)) { parts.append("toujours dans \(tab.title)") }
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
