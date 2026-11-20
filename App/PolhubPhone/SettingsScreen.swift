import PolhubLink
import SwiftUI
import UserNotifications

/// Réglages: which Mac this iPhone reads, the notifications, and how to unpair it.
struct PhoneSettingsScreen: View {
    @Environment(PhoneSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var notifications: UNAuthorizationStatus?

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    LabeledContent("Adresse", value: session.connection?.address.host() ?? "—")
                    LabeledContent("Polhub sur le Mac", value: session.status?.appVersion ?? "—")
                    LabeledContent("Cet iPhone", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
                Section {
                    LabeledContent("Notifications", value: notificationsText)
                    if notifications == .denied {
                        Button("Ouvrir les Réglages de l'iPhone") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } else if notifications == .notDetermined {
                        Button("Activer les notifications") {
                            Task {
                                await PhoneAppDelegate.ask()
                                notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                            }
                        }
                    }
                    LabeledContent("Adresse donnée au Mac", value: session.pushGivenAt.map { "à " + LinkWords.time($0) } ?? "pas encore")
                    if let problem = session.pushProblem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Chaque nouveau mail, les rendez-vous, les rappels et les comptes rendus arrivent ici quand le Mac est allumé.")
                }
                Section {
                    Button("Délier cet iPhone", role: .destructive) { confirming = true }
                } footer: {
                    Text("L'iPhone oublie le Mac et efface sa copie. Pour le relier de nouveau, scanne un nouveau code sur le Mac.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task {
                await session.refreshStatus()
                notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
            .confirmationDialog("Délier cet iPhone ?", isPresented: $confirming) {
                Button("Délier", role: .destructive) { session.unpair() }
            }
        }
    }

    private var notificationsText: String {
        switch notifications {
        case .authorized?, .provisional?, .ephemeral?: "Activées"
        case .denied?: "Refusées"
        default: "—"
        }
    }
}
