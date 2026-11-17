import AppKit
import PolhubDesign
import SwiftUI

/// The probe of Colin as the Diagnostic page shows it (17/11): the Claude account it uses, its one button, and where
/// it stands. The app runs the probe; this says when it may, and stops it when a meeting begins.
@MainActor
public final class ColinProbeControl: ObservableObject {
    public enum Phase: Equatable {
        case idle, running
        /// Over: `true` everything answered, `false` a point is to be looked at, `nil` no report.
        case done(Bool?)
        case refused(String)
    }

    @Published public private(set) var phase: Phase = .idle
    /// The folder of the Claude account; empty: Claude Code's own.
    @Published public private(set) var accountFolder: String

    private let defaults: UserDefaults
    private let isQuiet: () async -> Bool
    private let start: (_ account: String, _ onFinish: @escaping @MainActor (String?) -> Void) -> Bool
    private let stop: () -> Void
    private let report: () -> (ok: Bool, reason: String?)?
    private let folderExists: (String) -> Bool
    private let isAccount: (String) -> Bool
    private let watchEvery: Duration
    private var watcher: Task<Void, Never>?
    /// A click is being checked: a second one, of a double click, does nothing.
    private var launching = false
    private var stoppedForMeeting = false
    /// Why the last probe stopped early, as the probe names it.
    private var reason: String?

    /// - Parameters:
    ///   - isQuiet: no meeting and no transcription under way.
    ///   - start: starts the probe on this account's folder; `false` when another probe runs.
    ///   - stop: stops the probe under way.
    ///   - report: what the last probe concluded, and why it stopped early when it knows.
    ///   - isAccount: the folder holds a Claude account (Claude Code keeps a `.claude.json` in each).
    public init(defaults: UserDefaults = .standard, isQuiet: @escaping () async -> Bool,
                start: @escaping (_ account: String, _ onFinish: @escaping @MainActor (String?) -> Void) -> Bool,
                stop: @escaping () -> Void, report: @escaping () -> (ok: Bool, reason: String?)?,
                folderExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                isAccount: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0 + "/.claude.json") },
                watchEvery: Duration = .seconds(3)) {
        self.defaults = defaults
        self.isQuiet = isQuiet
        self.start = start
        self.stop = stop
        self.report = report
        self.folderExists = folderExists
        self.isAccount = isAccount
        self.watchEvery = watchEvery
        accountFolder = defaults.string(forKey: Preferences.Key.colinAccount) ?? ""
    }

    /// « comptes/second »: the end of the folder's path, enough to know it.
    public var accountLabel: String {
        guard !accountFolder.isEmpty else { return "Le compte de Claude Code" }
        return accountFolder.split(separator: "/").suffix(2).joined(separator: "/")
    }

    /// `nil` or empty: Claude Code's own account.
    public func choose(_ folder: String?) {
        var path = folder ?? ""
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        accountFolder = path
        defaults.set(path, forKey: Preferences.Key.colinAccount)
    }

    public func launch() async {
        guard phase != .running, !launching else { return }
        launching = true
        defer { launching = false }
        guard await isQuiet() else {
            phase = .refused("Pas pendant une réunion ni une transcription.")
            return
        }
        if !accountFolder.isEmpty {
            guard folderExists(accountFolder) else {
                phase = .refused("Ce dossier de compte n'existe plus.")
                return
            }
            // Any folder can be chosen in the panel, and Claude Code would write its own files in it.
            guard isAccount(accountFolder) else {
                phase = .refused("Ce dossier n'est pas celui d'un compte Claude.")
                return
            }
        }
        stoppedForMeeting = false
        reason = nil
        let started = start(accountFolder) { [weak self] _ in self?.finished() }
        guard started else {
            phase = .refused("Une autre sonde tourne déjà.")
            return
        }
        phase = .running
        watch()
    }

    /// Nothing heavy during a meeting: one that begins stops the probe. The app says it at once; `watch` looks
    /// again every few seconds, for a transcription that starts.
    public func meetingBegan() {
        guard phase == .running, !stoppedForMeeting else { return }
        stoppedForMeeting = true
        stop()
    }

    private func watch() {
        watcher?.cancel()
        watcher = Task { [weak self, watchEvery] in
            while !Task.isCancelled {
                try? await Task.sleep(for: watchEvery)
                guard let self, self.phase == .running, !Task.isCancelled else { return }
                let quiet = await self.isQuiet()
                // The probe may have ended while the check was waiting.
                guard self.phase == .running, !Task.isCancelled else { return }
                if !quiet {
                    self.meetingBegan()
                    return
                }
            }
        }
    }

    private func finished() {
        watcher?.cancel()
        watcher = nil
        let report = stoppedForMeeting ? nil : report()
        reason = report?.reason
        phase = .done(report?.ok)
    }

    /// The sentence under the button.
    public var message: String? {
        switch phase {
        case .idle: nil
        case .running: "La sonde tourne. Tu peux continuer à travailler."
        case .refused(let reason): reason
        case .done(true): "Terminé : Claude Code a répondu. Le relevé est enregistré."
        case .done(false): "Terminé : \(Self.sentence(reason) ?? "un point est à regarder.") Le relevé est enregistré."
        case .done(nil): stoppedForMeeting ? "Arrêtée : une réunion commence. Relance la sonde après." : "La sonde s'est arrêtée avant la fin."
        }
    }

    /// Why the probe stopped early, in words; `nil` for a reason this version does not know.
    static func sentence(_ reason: String?) -> String? {
        switch reason {
        case "introuvable": "Claude Code est introuvable sur ce Mac."
        case "pas-connecte": "Claude Code n'est pas connecté sur ce compte."
        case "sans-reponse": "Claude Code n'a pas répondu."
        case "lancement-impossible": "Claude Code n'a pas pu se lancer."
        default: nil
        }
    }
}

/// « Sonde de Colin » on the Diagnostic page.
struct ColinProbeSection: View {
    @ObservedObject var control: ColinProbeControl

    private var isRunning: Bool { control.phase == .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sonde de Colin").font(.headline)
            Text("Mesure si Claude Code répond bien depuis Polhub. Deux à trois minutes, avec des textes inventés. Elle utilise un peu de ton abonnement Claude : quelques centimes.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("Compte : \(control.accountLabel)").font(.callout)
                Button("Choisir…", action: chooseFolder)
                if !control.accountFolder.isEmpty {
                    Button("Compte de Claude Code") { control.choose(nil) }
                }
            }
            .disabled(isRunning)
            HStack(spacing: 8) {
                Button("Lancer la sonde de Colin") { Task { await control.launch() } }
                    .disabled(isRunning)
                if isRunning { ProgressView().controlSize(.small) }
            }
            if let message = control.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(isRefusal ? Color.orange : Color.secondary)
            }
        }
    }

    private var isRefusal: Bool {
        if case .refused = control.phase { return true }
        return false
    }

    /// The accounts' folders are often hidden ones: the panel shows them.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Choisir"
        panel.message = "Le dossier du compte Claude que Colin utilisera"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        control.choose(url.path(percentEncoded: false))
    }
}
