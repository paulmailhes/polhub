import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// Réglages › Calendrier (Paul, 14/11): the Google accounts and their colors, the new events, the week.
struct CalendarSettingsPane: View {
    @ObservedObject var agenda: AgendaLibrary
    @AppStorage(Preferences.Key.defaultAccount) private var defaultAccount = ""
    @AppStorage(Preferences.Key.eventMinutes) private var eventMinutes = Preferences.Default.eventMinutes
    @AppStorage(Preferences.Key.eventMeet) private var eventMeet = true
    @AppStorage(Preferences.Key.showWeekend) private var showWeekend = true
    @AppStorage(Preferences.Key.dayStartHour) private var dayStartHour = Preferences.Default.dayStartHour
    @State private var leaving: GoogleAccountRow?

    var body: some View {
        Form {
            Section {
                ForEach(agenda.accounts) { account in AccountSettingsRow(account: account, agenda: agenda) { leaving = account } }
                Button { Task { await agenda.connect() } } label: { Label("Ajouter un compte Google…", systemImage: "plus") }
                    .buttonStyle(.borderless)
                    .disabled(!agenda.hasGoogleKey)
                if let message = agenda.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Comptes Google")
            } footer: {
                Text("La couleur d'un compte marque ses rendez-vous dans le Calendrier et l'Accueil.")
            }
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
            Section {
                SyncStatus(agenda: agenda)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
        .confirmationDialog("Déconnecter \(leaving?.email ?? "") ?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })) {
            Button("Déconnecter", role: .destructive) {
                if let email = leaving?.email { Task { await agenda.disconnect(email) } }
                leaving = nil
            }
        } message: {
            Text("Ses rendez-vous disparaissent de Polhub ; rien ne change chez Google.")
        }
    }
}

/// One account: its name, its address, its state, its color.
struct AccountSettingsRow: View {
    let account: GoogleAccountRow
    @ObservedObject var agenda: AgendaLibrary
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ColorDot(agenda.color(for: account.email), size: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(AccountStyle.label(for: account.email)).font(.headline)
                    Text(account.email).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Déconnecter…", role: .destructive, action: disconnect).buttonStyle(.borderless).font(.callout)
            }
            HStack(spacing: Space.s) {
                ForEach(AccountStyle.choices, id: \.self) { hex in
                    let chosen = agenda.colors[account.email] == hex
                    Button { agenda.setColor(hex, for: account.email) } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                            .overlay { if chosen { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) } }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let error = account.lastError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let last = account.lastSyncAt {
                Text("Lu à \(last.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, Space.xs)
    }
}
