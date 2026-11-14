import Agenda
import AppKit
import Domain
import Mail
import Persistence
import PolhubDesign
import SwiftUI

/// Réglages › Comptes Google (14/11): the accounts the calendar and the mails share, their colors, what each
/// granted, and the measures taken before the mails are built.
struct AccountsSettingsPane: View {
    @ObservedObject var agenda: AgendaLibrary
    @StateObject private var measures = MailMeasures()
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
                Text("Comptes")
            } footer: {
                Text("La couleur d'un compte marque ses rendez-vous dans le Calendrier et l'Accueil. « Autoriser les mails » ouvre la page de Google ; l'agenda du compte reste connecté quoi que tu répondes.")
            }
            MailMeasuresSection(agenda: agenda, measures: measures)
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640)
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
                Text("Agenda lu à \(last.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            if agenda.mailGranted(account) {
                Label("Mails autorisés", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            } else {
                HStack(spacing: Space.s) {
                    Text("Mails pas encore autorisés").font(.caption).foregroundStyle(.secondary)
                    Button("Autoriser les mails") { Task { await agenda.authorizeMail(account.email) } }
                        .controlSize(.small)
                        .disabled(!agenda.hasGoogleKey)
                }
            }
        }
        .padding(.vertical, Space.xs)
    }
}

/// The measures of step 0 of the mails, and its two short essays. Leaves with the arrival of the mails.
struct MailMeasuresSection: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var measures: MailMeasures

    private var authorized: [GoogleAccountRow] { agenda.accounts.filter(agenda.mailGranted) }

    var body: some View {
        Section {
            Button { Task { await measures.run(agenda: agenda) } } label: {
                Label(measures.running ? "Mesure en cours…" : "Mesurer les boîtes autorisées", systemImage: "gauge.with.dots.needle.33percent")
            }
            .buttonStyle(.borderless)
            .disabled(measures.running || authorized.isEmpty)
            ForEach(measures.progress.keys.sorted(), id: \.self) { account in
                Text("\(AccountStyle.label(for: account)) : \(measures.progress[account] ?? "")").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(measures.reports, id: \.account) { report in
                Text(MailMeasures.summary(report)).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            if let file = measures.reportFile {
                Button("Montrer le rapport dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(.link)
            }
            HStack(spacing: Space.m) {
                Button("Essai du lien Gmail") { Task { await measures.openInGmail(agenda: agenda) } }
                Button("Essai de corbeille") { Task { await measures.trashEssay(agenda: agenda) } }
            }
            .controlSize(.small)
            .disabled(measures.running || authorized.isEmpty)
            if let essay = measures.essay { Text(essay).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        } header: {
            Text("Mesures avant les mails")
        } footer: {
            Text("Polhub ne relève ici que des nombres : jamais un objet, un texte ni l'adresse d'un correspondant. « Essai de corbeille » met à la corbeille puis rétablit un mail que tu t'es envoyé avec l'objet « \(MailTrashEssay.subject) ». Cette section partira avec l'arrivée des mails.")
        }
    }
}

/// Runs the measures of the mails and writes their report in the app's data folder.
@MainActor
final class MailMeasures: ObservableObject {
    @Published var running = false
    /// Account → the step under way.
    @Published var progress: [String: String] = [:]
    @Published var reports: [MailProbeReport] = []
    @Published var reportFile: URL?
    @Published var essay: String?

    /// Where the reports go: beside the base, never in the repository.
    static var folder: URL { AppPaths.standard(AppFlavor.current).root.appending(path: "Mesures", directoryHint: .isDirectory) }

    static func summary(_ report: MailProbeReport) -> String {
        if let error = report.errors.first, report.messagesTotal == 0 { return "\(AccountStyle.label(for: report.account)) : mesure impossible (\(error))" }
        return "\(AccountStyle.label(for: report.account)) : \(report.sixMonthsCounted ? "" : "plus de ")\(report.sixMonthsMessages) messages sur six mois, "
            + "\(report.inboxThreads) fils en réception, \(report.paced.quotaRefusals) refus de quota sur \(report.paced.reads + report.paced.quotaRefusals + report.paced.otherErrors) lectures"
    }

    func run(agenda: AgendaLibrary) async {
        guard !running else { return }
        running = true
        defer { running = false }
        reports = []
        reportFile = nil
        let accounts = agenda.accounts.filter(agenda.mailGranted).map(\.email)
        progress = Dictionary(uniqueKeysWithValues: accounts.map { ($0, "démarrage") })
        var done: [MailProbeReport] = []
        await withTaskGroup(of: MailProbeReport.self) { group in
            for account in accounts {
                let send = agenda.mailSend(for: account)
                group.addTask {
                    await MailProbe(send: send).run(account: account) { step in
                        Task { @MainActor [weak self] in self?.progress[account] = step }
                    }
                }
            }
            for await report in group {
                done.append(report)
                progress[report.account] = nil
            }
        }
        reports = done.sorted { $0.account < $1.account }
        progress = [:]
        reportFile = try? Self.write(reports, at: Date())
    }

    /// The report, readable and as JSON; returns the readable file.
    static func write(_ reports: [MailProbeReport], at date: Date, in folder: URL = MailMeasures.folder) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "mails-\(format.string(from: date))"
        let text = "Mesures des mails — \(date.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "fr_FR"))))\n"
            + "Des nombres seulement : aucun objet, aucun texte, aucune adresse de correspondant.\n\n"
            + reports.map(\.text).joined(separator: "\n\n") + "\n"
        let file = folder.appending(path: "\(name).txt")
        try Data(text.utf8).write(to: file, options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(reports).write(to: folder.appending(path: "\(name).json"), options: .atomic)
        return file
    }

    /// Opens the most recent thread of the first authorized mailbox in Gmail's own page: Paul says whether the
    /// right mail opened under the right account.
    func openInGmail(agenda: AgendaLibrary) async {
        guard let account = agenda.accounts.first(where: agenda.mailGranted)?.email else { return }
        do {
            let data = try await agenda.mailSend(for: account)({ GmailAPI.threadsRequest(accessToken: $0, labelIDs: ["INBOX"], maxResults: 1) })
            guard let thread = try GmailAPI.decode(GmailAPI.IDPage.self, from: data).ids.first else {
                essay = "La boîte de réception de \(account) est vide."
                return
            }
            NSWorkspace.shared.open(GmailLink.thread(thread, account: account))
            essay = "Le dernier fil de \(AccountStyle.label(for: account)) s'ouvre dans ton navigateur : est-ce le bon mail, sous le bon compte ?"
        } catch {
            essay = "Essai impossible : \(error)"
        }
    }

    /// Trashes then restores the test mail, in the first authorized mailbox that holds one.
    func trashEssay(agenda: AgendaLibrary) async {
        essay = "Essai de corbeille en cours…"
        var last = MailTrashEssay()
        for account in agenda.accounts.filter(agenda.mailGranted).map(\.email) {
            last = await MailTrashEssay.run(send: agenda.mailSend(for: account))
            if last.found || last.error != nil {
                essay = "\(AccountStyle.label(for: account)) — \(last.text)"
                try? Data((essay! + "\n").utf8).write(to: Self.folder.appending(path: "mails-essai-corbeille.txt"), options: .atomic)
                return
            }
        }
        essay = last.text
    }
}
