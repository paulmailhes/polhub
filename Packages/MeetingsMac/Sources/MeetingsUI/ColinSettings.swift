import PolhubDesign
import SwiftUI

/// The words of Réglages › Colin (18/11).
enum ColinSettingsText {
    /// What leaves the Mac when Colin is on.
    static let footer = "Colin allumé, ce que tu lui écris, « Ce que Colin sait », vos derniers échanges, les lignes de l'Accueil et ce qu'il lit pour te répondre partent chez Anthropic par ton Claude Code. Jamais l'audio ni les pièces jointes. Il n'envoie rien : un brouillon t'attend toujours. Il change le kanban quand tu le lui demandes, et chaque changement s'annule depuis l'Accueil."

    /// « Colin tient le kanban seul » (step 3, 18/11): its two rules, made on the Mac, with no model.
    static let kanban = "Colin en marche, après un mail que tu envoies dans un fil de projet : priorité 1 et « En attente retour de … ». Un rendez-vous pris dans un projet devient l'échéance si elle est vide ou passée. Jamais un projet en pause ou terminé, ni ce que tu as changé toi-même aujourd'hui. Chaque changement s'affiche dans le fil de Colin, avec « Annuler »."

    /// The read-only line: what Colin did this week, and what the API would have charged for it.
    static func week(count: Int, costUSD: Double) -> String {
        guard count > 0 else { return "Cette semaine : aucune réponse de Colin." }
        let cost = String(format: "%.2f", costUSD).replacingOccurrences(of: ".", with: ",")
        return "Cette semaine : \(count) réponse\(count > 1 ? "s" : "") de Colin, l'équivalent de \(cost) $."
    }
}

/// Réglages › Colin (18/11): the switch (the same as the Accueil's), the account, « Ce que Colin sait », what he did
/// this week, and what the Accueil signals.
struct ColinSettingsPane: View {
    var thread: ColinThread?
    var probe: ColinProbeControl?
    @AppStorage(Preferences.Key.colinReplyDays) private var replyDays = Preferences.Default.colinReplyDays
    @AppStorage(Preferences.Key.colinSilentDays) private var silentDays = Preferences.Default.colinSilentDays
    @AppStorage(Preferences.Key.colinKanban) private var kanban = false
    @State private var knowledge = ""
    @State private var week = ""

    var body: some View {
        Form {
            if let thread {
                Section {
                    ColinSwitch(thread: thread)
                    if let probe { ColinAccountRow(control: probe) }
                    Text(week).font(.meta).foregroundStyle(.secondary)
                } footer: {
                    Text(ColinSettingsText.footer).font(.meta)
                }
                Section {
                    Toggle("Colin tient le kanban seul", isOn: $kanban)
                } footer: {
                    Text(ColinSettingsText.kanban).font(.meta)
                }
                Section {
                    // Kept a second after the last keystroke, and at once when Paul leaves the page.
                    TextEditor(text: $knowledge)
                        .font(.rowBody)
                        .frame(minHeight: 160)
                        .onChange(of: knowledge) { _, text in if text != thread.knowledge { thread.editKnowledge(text) } }
                        .onDisappear { thread.flushKnowledge() }
                } header: {
                    Text("Ce que Colin sait")
                } footer: {
                    Text("Ce que Colin relit au début de chaque échange : ta façon d'écrire, ton lien de rendez-vous, ce qu'il doit savoir de tes clients. Il ne le change jamais lui-même : « Garder », dans le fil, y ajoute une ligne.")
                        .font(.meta)
                }
            }
            Section {
                Picker("Signaler un mail sans réponse après",
                       selection: shown($replyDays, among: Preferences.Default.colinReplyChoices, or: Preferences.Default.colinReplyDays)) {
                    ForEach(Preferences.Default.colinReplyChoices, id: \.self) { Text("\($0) jours").tag($0) }
                }
                Picker("Signaler un client muet après",
                       selection: shown($silentDays, among: Preferences.Default.colinSilentChoices, or: Preferences.Default.colinSilentDays)) {
                    ForEach(Preferences.Default.colinSilentChoices, id: \.self) { Text("\($0) jours").tag($0) }
                }
            } header: {
                Text("À valider")
            } footer: {
                Text("Un mail attend ta réponse quand une personne t'a écrit et que tu ne lui as rien écrit depuis, dans aucun fil : après le délai choisi, et jusqu'à 14 jours. Un client est muet quand ton dernier mail d'un projet reste sans réponse, dans aucun fil, sans rendez-vous depuis ni à venir.")
                    .font(.meta)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .onAppear {
            guard let thread else { return }
            knowledge = thread.knowledge
            let done = thread.week()
            week = ColinSettingsText.week(count: done.count, costUSD: done.costUSD)
        }
    }

    /// What the list shows is what applies: a stored value out of the choices shows as the default.
    private func shown(_ stored: Binding<Int>, among choices: [Int], or fallback: Int) -> Binding<Int> {
        Binding(get: { Preferences.choice(stored.wrappedValue, among: choices, or: fallback) }, set: { stored.wrappedValue = $0 })
    }
}

/// The one switch of Colin, the same as the Accueil's.
private struct ColinSwitch: View {
    @ObservedObject var thread: ColinThread

    var body: some View {
        Toggle("Colin", isOn: Binding(get: { thread.status != .off }, set: { $0 ? thread.turnOn() : thread.turnOff() }))
    }
}
