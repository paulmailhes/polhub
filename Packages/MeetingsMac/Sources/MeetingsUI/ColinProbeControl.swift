import AppKit
import Colin
import PolhubDesign
import SwiftUI

/// The probe of Colin as the Diagnostic page shows it (17/11): the Claude account it uses, its button, and where it
/// stands. The app runs the probe; this says when it may, and stops it when a meeting begins, when the Mac goes to
/// sleep, or by hand.
@MainActor
public final class ColinProbeControl: ObservableObject {
    public enum Phase: Equatable {
        case idle, running
        /// Over: `true` everything answered, `false` a point is to be looked at, `nil` no report.
        case done(Bool?)
        case refused(String)
    }

    /// Why a probe under way was stopped from here.
    private enum StopCause { case meeting, hand, sleep }

    @Published public private(set) var phase: Phase = .idle
    /// The folder of the Claude account; empty: Claude Code's own.
    @Published public private(set) var accountFolder: String

    private let defaults: UserDefaults
    private let home: URL
    private let isQuiet: () async -> Bool
    private let start: (_ account: String, _ onFinish: @escaping @MainActor (String?) -> Void) -> String?
    private let stop: () -> Void
    private let report: () -> (ok: Bool, reason: String?)?
    private let folderExists: (String) -> Bool
    private let isAccount: (String) -> Bool
    private let uptime: () -> TimeInterval
    private let sinceWake: () -> TimeInterval?
    private let watchEvery: Duration
    private let settleAfterWake: Duration
    private let restAfterFinish: Duration
    private let clock = ContinuousClock()
    private var watcher: Task<Void, Never>?
    /// A click is being checked: a second one, of a double click, does nothing.
    private var launching = false
    private var stopCause: StopCause?
    /// Why the last probe stopped early, as the probe names it.
    private var reason: String?
    /// What the app's runner said of a run it could not carry to its end.
    private var problem: String?
    private var wokeAt: ContinuousClock.Instant?
    private var finishedAt: ContinuousClock.Instant?

    /// - Parameters:
    ///   - home: the user's own folder; Claude Code's own account lives in its `.claude`.
    ///   - isQuiet: no meeting and no transcription under way.
    ///   - start: starts the probe on this account's folder; why it could not, or `nil` once started.
    ///   - stop: stops the probe under way.
    ///   - report: what the last probe concluded, and why it stopped early when it knows; `nil` without a report.
    ///   - isAccount: the folder holds a Claude account (Claude Code keeps a `.claude.json` in each).
    ///   - uptime: seconds since the Mac started.
    ///   - sinceWake: seconds since the Mac last woke, as the system says it; `nil`: it has not slept since it
    ///     started.
    ///   - watchEvery: how often a probe under way looks for a meeting or a transcription that begins.
    ///   - settleAfterWake: how long nothing is launched after the Mac starts or wakes.
    ///   - restAfterFinish: how long a click is ignored after a probe ends.
    public init(defaults: UserDefaults = .standard, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                isQuiet: @escaping () async -> Bool,
                start: @escaping (_ account: String, _ onFinish: @escaping @MainActor (String?) -> Void) -> String?,
                stop: @escaping () -> Void, report: @escaping () -> (ok: Bool, reason: String?)?,
                folderExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                isAccount: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0 + "/.claude.json") },
                uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                sinceWake: @escaping () -> TimeInterval? = { ColinProbeControl.systemSinceWake() },
                watchEvery: Duration = ColinProbeControl.watchPace, settleAfterWake: Duration = ColinProbeControl.settling,
                restAfterFinish: Duration = ColinProbeControl.rest) {
        self.defaults = defaults
        self.home = home
        self.isQuiet = isQuiet
        self.start = start
        self.stop = stop
        self.report = report
        self.folderExists = folderExists
        self.isAccount = isAccount
        self.uptime = uptime
        self.sinceWake = sinceWake
        self.watchEvery = watchEvery
        self.settleAfterWake = settleAfterWake
        self.restAfterFinish = restAfterFinish
        accountFolder = defaults.string(forKey: Preferences.Key.colinAccount) ?? ""
    }

    /// A probe under way looks this often for a meeting or a transcription that begins.
    public nonisolated static let watchPace: Duration = .seconds(3)
    /// Nothing is launched for this long after the Mac starts or wakes (the design of 17/11: five minutes).
    public nonisolated static let settling: Duration = .seconds(300)
    /// A click is ignored for this long after a probe ends.
    public nonisolated static let rest: Duration = .seconds(1)

    /// How long ago the Mac last woke, in seconds, as the system keeps it: a Polhub opened after the wake, or
    /// relaunched by its own update, did not see it happen. Read on the clock that counts the time awake, which a
    /// change of the date cannot move (measured on 18/11: within a second of the dated one). `nil`: the Mac has not
    /// slept since it started.
    public nonisolated static func systemSinceWake() -> TimeInterval? {
        var woke: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("kern.wake_abs_time", &woke, &size, nil, 0) == 0, woke > 0 else { return nil }
        var base = mach_timebase_info_data_t()
        guard mach_timebase_info(&base) == KERN_SUCCESS, base.denom > 0 else { return nil }
        let now = mach_absolute_time()
        guard now >= woke else { return nil }
        return Double(now - woke) * Double(base.numer) / Double(base.denom) / 1_000_000_000
    }

    /// « comptes/second »: the end of the folder's path, enough to know it.
    public var accountLabel: String {
        guard !accountFolder.isEmpty else { return "Le compte de Claude Code" }
        return accountFolder.split(separator: "/").suffix(2).joined(separator: "/")
    }

    /// `nil` or empty: Claude Code's own account. Its own folder, chosen by hand, is its own account too: given as
    /// a folder, it would name another one.
    public func choose(_ folder: String?) {
        guard phase != .running else { return }
        let path = ClaudeCommand.account(folder: folder, home: home).map(Self.plain) ?? ""
        if let refusal = unfit(path) {
            phase = .refused(refusal)
            return
        }
        accountFolder = path
        defaults.set(path, forKey: Preferences.Key.colinAccount)
        // What was said was about the account before.
        phase = .idle
    }

    /// The user's own folder, or the disk's root: no account's folder. Claude Code keeps the file of its own
    /// account in the first, which would pass for one, and would then write everything there.
    private func unfit(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let chosen = URL(fileURLWithPath: path, isDirectory: true)
        guard Self.plain(chosen) != "/", !Self.same(chosen, home) else {
            return "Choisis le dossier d'un compte Claude, pas ton dossier personnel."
        }
        return nil
    }

    /// A folder's path with no slash at its end.
    private static func plain(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// The same folder, written the same way or not (a link to it, another case): compared as the disk knows them.
    private static func same(_ one: URL, _ other: URL) -> Bool {
        let first = one.standardizedFileURL.resolvingSymlinksInPath(), second = other.standardizedFileURL.resolvingSymlinksInPath()
        if plain(first) == plain(second) { return true }
        guard let left = (try? first.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier,
              let right = (try? second.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier else { return false }
        return left.isEqual(right)
    }

    /// Each launch of Claude Code may renew the connection of its account, and the keychain chokes when many do at
    /// once: nothing in the minutes after the Mac starts or wakes.
    private var settled: Bool {
        let wait = Double(settleAfterWake.components.seconds) + Double(settleAfterWake.components.attoseconds) / 1e18
        if uptime() < wait { return false }
        // The wake this copy saw, and the one the system remembers when this copy was not there to see it.
        if let wokeAt, clock.now - wokeAt < settleAfterWake { return false }
        if let since = sinceWake(), since < wait { return false }
        return true
    }

    public func launch() async {
        guard phase != .running, !launching else { return }
        // Right after a probe ended: the second click of a double click on « Arrêter », not a new launch.
        if let finishedAt, clock.now - finishedAt < restAfterFinish { return }
        launching = true
        defer { launching = false }
        guard settled else {
            phase = .refused("Le Mac vient de démarrer ou de se réveiller : réessaie dans quelques minutes.")
            return
        }
        guard await isQuiet() else {
            phase = .refused("Pas pendant une réunion ni une transcription.")
            return
        }
        // From here to the start, nothing waits: a meeting cannot begin in between.
        if !accountFolder.isEmpty {
            if let refusal = unfit(accountFolder) {
                phase = .refused(refusal)
                return
            }
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
        stopCause = nil
        reason = nil
        problem = nil
        if let refusal = start(accountFolder, { [weak self] problem in self?.finished(problem) }) {
            phase = .refused(refusal)
            return
        }
        phase = .running
        watch()
    }

    /// Nothing heavy during a meeting: one that begins stops the probe. The app says it at once; `watch` looks
    /// again every few seconds, for a transcription that starts.
    public func meetingBegan() { halt(.meeting) }

    /// « Arrêter ».
    public func stopByHand() { halt(.hand) }

    /// The Mac goes to sleep: what the probe would time across the night means nothing.
    public func macWillSleep() { halt(.sleep) }

    /// The Mac woke up: nothing is launched for a few minutes.
    public func macWoke() { wokeAt = clock.now }

    /// Asked once; the probe still runs until the app says it ended.
    private func halt(_ cause: StopCause) {
        guard phase == .running, stopCause == nil else { return }
        stopCause = cause
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
                    self.halt(.meeting)
                    return
                }
            }
        }
    }

    private func finished(_ problem: String?) {
        watcher?.cancel()
        watcher = nil
        finishedAt = clock.now
        self.problem = problem
        // A probe that reached its end left its report: it is shown, even when a stop was asked at that moment.
        let report = report()
        reason = report?.reason
        phase = .done(report?.ok)
    }

    /// The sentence under the button.
    public var message: String? {
        switch phase {
        case .idle: return nil
        case .running: return "La sonde tourne. Tu peux continuer à travailler."
        case .refused(let reason): return reason
        case .done(true): return "Terminé : Claude Code a répondu. Le relevé est enregistré."
        case .done(false): return "Terminé : \(Self.sentence(reason) ?? "un point est à regarder.") Le relevé est enregistré."
        case .done(nil):
            switch stopCause {
            case .meeting: return "Arrêtée : une réunion ou une transcription commence. Relance la sonde après."
            case .hand: return "Arrêtée."
            case .sleep: return "Arrêtée : le Mac s'est mis en veille."
            case nil: return problem ?? "La sonde s'est arrêtée avant la fin."
            }
        }
    }

    /// Why the probe stopped early, in words that follow « Terminé : »; `nil` for a reason this version does not
    /// know.
    static func sentence(_ reason: String?) -> String? {
        switch reason {
        case "introuvable": "Claude Code est introuvable sur ce Mac."
        case "pas-connecte": "Claude Code n'est pas connecté sur ce compte."
        case "limite-atteinte": "ton compte Claude a atteint sa limite."
        case "sans-reponse": "Claude Code n'a pas répondu."
        case "lancement-impossible": "Claude Code n'a pas pu se lancer."
        case "isolation": "Claude Code a chargé plus que ce que Polhub lui demande."
        case "isolation-inconnue": "Polhub n'a pas pu vérifier ce que Claude Code a chargé."
        case "erreur": "Claude Code a répondu par une erreur dès le premier lancement."
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
            Text("Mesure si Claude Code répond bien depuis Polhub. Environ deux minutes, avec des textes inventés. Elle utilise un peu de ton abonnement Claude : l'équivalent d'une dizaine de centimes.")
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
                if isRunning {
                    ProgressView().controlSize(.small)
                    Button("Arrêter") { control.stopByHand() }
                }
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
