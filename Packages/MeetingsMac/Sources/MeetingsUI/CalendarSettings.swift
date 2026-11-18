import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// Réglages › Calendrier (Paul, 14/11): the new events, the week. The accounts live in Réglages › Comptes Google.
struct CalendarSettingsPane: View {
    @ObservedObject var agenda: AgendaLibrary
    @AppStorage(Preferences.Key.defaultAccount) private var defaultAccount = ""
    @AppStorage(Preferences.Key.eventMinutes) private var eventMinutes = Preferences.Default.eventMinutes
    @AppStorage(Preferences.Key.eventMeet) private var eventMeet = true
    @AppStorage(Preferences.Key.showWeekend) private var showWeekend = true
    @AppStorage(Preferences.Key.dayStartHour) private var dayStartHour = Preferences.Default.dayStartHour
    @AppStorage(Preferences.Key.homeTomorrowFrom) private var homeTomorrowFrom = Preferences.Default.homeTomorrowFrom

    var body: some View {
        Form {
            Section("Nouveaux rendez-vous") {
                Picker("Agenda par défaut", selection: $defaultAccount) {
                    Text("Le dernier utilisé").tag("")
                    ForEach(agenda.accounts) { account in
                        Text("\(AccountStyle.label(for: account.email)) · \(account.email)").tag(account.email)
                    }
                }
                Picker("Durée", selection: $eventMinutes) {
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 h").tag(60)
                    Text("1 h 30").tag(90)
                }
                Toggle("Visio Google Meet", isOn: $eventMeet)
            }
            Section("Affichage") {
                Toggle("Afficher le week-end", isOn: $showWeekend)
                Picker("La grille s'ouvre à", selection: $dayStartHour) {
                    ForEach([6, 7, 8, 9, 10], id: \.self) { Text("\($0) h").tag($0) }
                }
            }
            // 0.36.0: in the evening, the Accueil shows tomorrow's meetings, once today's last one is over.
            Section("Accueil") {
                Picker("L'Accueil montre demain à partir de", selection: $homeTomorrowFrom) {
                    ForEach(16...23, id: \.self) { Text("\($0) h").tag($0 * 60) }
                }
            }
            Section {
                SyncStatus(agenda: agenda)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
    }
}
