import PolhubLink
import SwiftUI

/// Polhub on the iPhone (20/11): Paul's mails, calendar, projects and meetings, read from his Mac by his Tailscale
/// network. The QR code of Réglages › iPhone on the Mac pairs it.
@main
struct PolhubPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @State private var session = PhoneSession()
    @State private var pairingProblem: String?
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                // Not paired, but with the Mac's copy from iCloud: the tabs show it (20/11).
                if session.connection == nil, !session.hasCopy {
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
            // At launch and back in front, the Mac's copy in iCloud.
            .task(id: phase) {
                guard phase == .active else { return }
                // Each time in front: the notifications' address goes again to the Mac, through iCloud (20/11).
                delegate.session = session
                if !session.demo { await PhoneAppDelegate.ask() }
                await session.refreshCloud()
                // The icon's number, as the Mac counts it now.
                await session.refreshStatus()
            }
            // Paired: the notifications are asked once, and their token goes to the Mac at each launch.
            .task(id: session.connection?.token) {
                delegate.session = session
                guard session.connection != nil, !session.demo else { return }
                await PhoneAppDelegate.ask()
            }
        }
    }
}

/// The tabs, as on the Mac's sidebar; Réglages behind the gear of each page. `-calendrier`, `-colin`, `-projets`,
/// `-reunions`: the tab open at launch (the captures).
struct RootTabs: View {
    @Environment(PhoneSession.self) private var session
    @State private var tab = Self.launchTab
    @State private var settings = ProcessInfo.processInfo.arguments.contains("-reglages")

    static var launchTab: Int {
        let arguments = ProcessInfo.processInfo.arguments
        return ["-calendrier", "-colin", "-projets", "-reunions"].firstIndex { arguments.contains($0) }.map { $0 + 1 } ?? 0
    }

    var body: some View {
        TabView(selection: $tab) {
            // Each tab on the color of its family on the Mac (Paul, 20/11: more color).
            Tab("Mails", systemImage: "envelope", value: 0) { MailsScreen().tint(PhoneStyle.mails) }
            Tab("Calendrier", systemImage: "calendar", value: 1) { CalendarScreen() }
            Tab("Colin", systemImage: "sparkles", value: 2) { ColinScreen().tint(PhoneStyle.colin) }
            Tab("Projets", systemImage: "square.grid.2x2", value: 3) { ProjectsScreen().tint(PhoneStyle.projects) }
            Tab("Réunions", systemImage: "waveform", value: 4) { MeetingsScreen().tint(PhoneStyle.meetings) }
        }
        .overlay(alignment: .bottom) { SendingPill().animation(.snappy, value: session.sending?.draftID) }
        // A touched notification: its tab.
        .onChange(of: session.opening) { _, opening in
            switch opening {
            case .thread?: tab = 0
            case .calendar?:
                tab = 1
                session.opening = nil
            case nil: break
            }
        }
        .environment(\.openSettings, OpenSettings { settings = true })
        .sheet(isPresented: $settings) { PhoneSettingsScreen() }
    }
}

/// The gear of each page, which opens Réglages.
struct OpenSettings {
    let action: () -> Void
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var openSettings = OpenSettings {}
}

/// The gear at the head of each tab's first page.
struct SettingsButton: ToolbarContent {
    @Environment(\.openSettings) private var openSettings

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { openSettings() } label: { Label("Réglages", systemImage: "gearshape") }
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
