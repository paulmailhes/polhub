import PolhubLink
import SwiftUI

/// Polhub on the iPhone (20/11): Paul's mails, calendar, projects and meetings, read from his Mac by his Tailscale
/// network. The QR code of Réglages › iPhone on the Mac pairs it.
@main
struct PolhubPhoneApp: App {
    @State private var session = PhoneSession()
    @State private var pairingProblem: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if session.connection == nil {
                    PairingScreen(problem: pairingProblem)
                } else {
                    RootTabs()
                }
            }
            .environment(session)
            .tint(.ink)
            // The QR code of the Mac opens here.
            .onOpenURL { url in
                Task { pairingProblem = await session.pair(with: url) }
            }
        }
    }
}

/// The tabs, as on the Mac's sidebar.
struct RootTabs: View {
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-calendrier") ? 1 : (ProcessInfo.processInfo.arguments.contains("-reglages") ? 2 : 0)

    var body: some View {
        TabView(selection: $tab) {
            Tab("Mails", systemImage: "envelope", value: 0) { MailsScreen() }
            Tab("Calendrier", systemImage: "calendar", value: 1) { CalendarScreen() }
            Tab("Réglages", systemImage: "gearshape", value: 2) { PhoneSettingsScreen() }
        }
    }
}

/// Before the first pairing: what to do on the Mac.
struct PairingScreen: View {
    let problem: String?
    @Environment(PhoneSession.self) private var session
    @State private var pasted: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "laptopcomputer.and.iphone").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Relie Polhub à ton Mac").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                Label("Sur le Mac, ouvre Polhub › Réglages › iPhone, puis « Relier un iPhone ».", systemImage: "1.circle")
                Label("Scanne le code avec l'appareil photo de cet iPhone.", systemImage: "2.circle")
            }
            .padding(.horizontal)
            if let message = pasted ?? problem {
                Text(message).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal)
            }
            Button("Coller le lien du code") {
                guard let text = UIPasteboard.general.string, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    pasted = "Copie d'abord le lien du code."
                    return
                }
                Task { pasted = await session.pair(with: url) }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}

/// « Mac injoignable · copie de 18:42 », or what went wrong.
struct StateLine: View {
    let keptAt: Date?
    let problem: String?

    var body: some View {
        if let keptAt {
            Label("Mac injoignable · \(LinkWords.kept(keptAt))", systemImage: "moon.zzz")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 6).background(.bar)
        } else if let problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(8).background(.bar)
        }
    }
}
