import PolhubDesign
import SwiftUI

/// Réglages › Colin (18/11): what Colin signals on the Accueil, in « À valider ». Two delays for now; the rest of
/// Colin's settings join them step by step.
struct ColinSettingsPane: View {
    @AppStorage(Preferences.Key.colinReplyDays) private var replyDays = Preferences.Default.colinReplyDays
    @AppStorage(Preferences.Key.colinSilentDays) private var silentDays = Preferences.Default.colinSilentDays

    var body: some View {
        Form {
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
                Text("Un mail attend ta réponse quand le dernier message du fil vient d'une personne à qui tu as déjà écrit. Un client est muet quand ton dernier message dans un fil de projet reste sans réponse, sans rendez-vous à venir.")
                    .font(.meta)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }

    /// What the list shows is what applies: a stored value out of the choices shows as the default.
    private func shown(_ stored: Binding<Int>, among choices: [Int], or fallback: Int) -> Binding<Int> {
        Binding(get: { Preferences.choice(stored.wrappedValue, among: choices, or: fallback) }, set: { stored.wrappedValue = $0 })
    }
}
