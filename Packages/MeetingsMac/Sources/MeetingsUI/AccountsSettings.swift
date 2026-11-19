import Agenda
import Persistence
import PolhubDesign
import SwiftUI

/// Réglages › Comptes Google (14/11): the accounts the calendar and the mails share, their colors, what each
/// granted.
struct AccountsSettingsPane: View {
    @ObservedObject var agenda: AgendaLibrary
    @State private var leaving: GoogleAccountRow?

    var body: some View {
        Form {
            Section {
                ForEach(agenda.accounts) { account in AccountSettingsRow(account: account, agenda: agenda) { leaving = account } }
                Button { Task { await agenda.connect() } } label: { Label("Ajouter un compte Google…", systemImage: "plus") }
                    .buttonStyle(.secondary)
                    .disabled(!agenda.hasGoogleKey)
                if let message = agenda.message { Text(message).font(.meta).foregroundStyle(.secondary) }
                // In the card, under what it explains (lot 7, 19/11): no paragraph under the card any more.
                SettingHelp(SettingsText.colorHelp)
            } header: {
                Text("Comptes")
            }
        }
        .settingsForm()
        .confirmationDialog("Déconnecter \(leaving?.email ?? "") ?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })) {
            Button("Déconnecter", role: .destructive) {
                if let email = leaving?.email { Task { await agenda.disconnect(email) } }
                leaving = nil
            }
        } message: {
            Text("Ses rendez-vous et ses mails disparaissent de Polhub ; rien ne change chez Google.")
        }
    }
}

/// One account: its name, its address, its color, its calendar's state, its mails' state.
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
                    Text(account.email).font(.meta).foregroundStyle(.secondary)
                }
                Spacer()
                // A rare gesture that no « Annuler » brings back: in the menu « … » of its account, with its question
                // (lot 7, 19/11), no longer the most visible button of each account.
                IconMenu("ellipsis", help: "Plus") {
                    Button("Déconnecter…", role: .destructive, action: disconnect)
                }
            }
            HStack(spacing: Space.xs) {
                ForEach(Array(AccountStyle.choices.enumerated()), id: \.element) { index, hex in
                    let chosen = agenda.colors[account.email] == hex
                    Button { agenda.setColor(hex, for: account.email) } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                            .overlay { if chosen { Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.white) } }
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.hover(.circle))
                    .help(chosen ? "La couleur de ce compte" : "Prendre cette couleur")
                    .accessibilityLabel("Couleur \(index + 1) sur \(AccountStyle.choices.count)")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            // Its error said by `ErrorLine`, « Mails autorisés » in the color of « done » (design system v2, 19/11).
            if let error = account.lastError {
                ErrorLine(error).font(.meta)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let last = account.lastSyncAt {
                Text("Agenda lu à \(last.formatted(date: .omitted, time: .shortened))").font(.meta).foregroundStyle(.secondary)
            }
            if agenda.mailGranted(account) {
                Label("Mails autorisés", systemImage: "checkmark.circle.fill").font(.meta).foregroundStyle(Tint.done)
            } else {
                HStack(spacing: Space.s) {
                    Text("Mails pas encore autorisés").font(.meta).foregroundStyle(.secondary)
                    Button("Autoriser les mails") { Task { await agenda.authorizeMail(account.email) } }
                        .controlSize(.small)
                        .disabled(!agenda.hasGoogleKey)
                    // What Google's page does, beside the button that opens it (lot 7, 19/11).
                    InfoBubble(SettingsText.mailGrantDetail)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }
}
