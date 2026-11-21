import AppKit
import Foundation
import VigieKit

/// Vigie in hub (21/11): what its engine says, read again every few seconds, and what Paul decides, sent back to it.
/// The engine is Vigie's own, already on the Mac; hub only talks to it. Since the migration (21/11, Paul: « complètement
/// désactiver mon Vigie, utiliser celui de Hub ») it does what the app Vigie did on its « Vue d'ensemble »: decide, answer,
/// change an answer, open Terminal, restart the engine, and the general settings.
@MainActor public final class VigieLibrary: ObservableObject {
    public enum Link: Equatable, Sendable {
        /// Not asked yet.
        case unknown
        /// The engine is not on this Mac.
        case absent
        /// It does not answer.
        case stopped
        case running
        /// It answers, but hub cannot use what it says: why.
        case trouble(String)
    }

    /// What hub does outside itself: the clipboard, a link, the engine's restart. Replaced in the tests.
    public struct Actions {
        public var copy: (String) -> Void
        public var open: (URL) -> Void
        /// Restarts the engine as the app Vigie did: `launchctl kickstart` of its agent. True when it went.
        public var restart: () async -> Bool
        /// The app Vigie is still on this Mac, where its engine would install its new versions.
        public var appInstalled: () -> Bool

        public init(copy: @escaping (String) -> Void, open: @escaping (URL) -> Void, restart: @escaping () async -> Bool,
                    appInstalled: @escaping () -> Bool = { true }) {
            self.copy = copy
            self.open = open
            self.restart = restart
            self.appInstalled = appInstalled
        }

        @MainActor public static var system: Actions { Actions(
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            open: { NSWorkspace.shared.open($0) },
            restart: { await VigieLibrary.kickstart() },
            appInstalled: { VigieLibrary.appIsInstalled() }
        ) }
    }

    @Published public private(set) var link: Link = .unknown
    @Published public private(set) var overview = VigieOverview()
    /// What a gesture said when it failed, once.
    @Published public var problem: String?
    /// What a gesture did that Paul must know (a message copied to paste), once.
    @Published public var info: String?
    /// What is being sent: their buttons wait.
    @Published public private(set) var sending: Set<String> = []
    /// What Paul decided, taken away at once (21/11, as the app Vigie): a read that left before the decision still
    /// holds it; it comes back only if the engine refused.
    @Published private var hidden: [String: Date] = [:]
    /// The page is on screen: read every 3 s; else every 20 s, for the count beside the section and the menu bar.
    public var isVisible = false {
        didSet {
            guard isVisible, !oldValue else { return }
            Task { await refresh() }
        }
    }

    let client: VigieClient
    let actions: Actions
    let defaults: UserDefaults
    /// After each reading that shows what the engine says now: the notifications (21/11).
    public var onRead: ((VigieOverview) -> Void)?
    private var loop: Task<Void, Never>?
    /// Reads missed in a row, and the last one that answered: « ne répond pas » after two, or eight seconds.
    private var misses = 0
    private var lastAnswer: Date?
    /// A write under way: a read that left before it is not shown.
    private var writes = 0

    public init(client: VigieClient = VigieClient(), actions: Actions? = nil, defaults: UserDefaults = .standard) {
        self.client = client
        self.actions = actions ?? .system
        self.defaults = defaults
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(self?.isVisible == true ? 3 : 20))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: - What the page shows

    /// What waits for Paul's decision now: Vigie's red count (a sensitive action, a question or a plan, a conversation
    /// that waits in VS Code), the soonest refusal first.
    public var decisions: [VigieReview] { overview.decisions.filter { hidden[$0.id] == nil } }
    /// The questions Vigie answered for Paul, to read again.
    public var toRead: [VigieReview] { overview.toRead.filter { hidden[$0.id] == nil } }
    /// What is only to see.
    public var toSee: [VigieReview] { overview.toSee.filter { hidden[$0.id] == nil } }
    public var settings: VigieSettings? { overview.settings }
    public var openConversations: [VigieConversation] { overview.conversations.filter { $0.status != .closed } }
    public var closedCount: Int { overview.conversations.count - openConversations.count }

    public func refresh() async {
        let started = writes
        do {
            let fresh = try await client.overview()
            misses = 0
            lastAnswer = Date()
            // A write happened while this read was on its way: what it says is older than the decision.
            guard started == writes else { return }
            // What the engine no longer lists needs no hiding; what it still lists stays hidden a minute at most.
            let listed = Set(fresh.toReview.map(\.id))
            hidden = hidden.filter { listed.contains($0.key) && Date().timeIntervalSince($0.value) < 60 }
            if fresh != overview { overview = fresh }
            set(.running)
            onRead?(fresh)
            if fresh.settings?.autoUpdate == true { await turnOffUpdatesWithoutTheApp() }
        } catch VigieFailure.absent {
            if overview != VigieOverview() { overview = VigieOverview() }
            set(.absent)
        } catch VigieFailure.stopped {
            misses += 1
            // One read missed is not a stopped engine (21/11: it answered late while it indexed).
            let late = lastAnswer.map { Date().timeIntervalSince($0) > 8 } ?? true
            if misses >= 2 || late { set(.stopped) }
        } catch {
            set(.trouble(Self.sentence(error)))
        }
    }

    private func set(_ link: Link) {
        if self.link != link { self.link = link }
    }

    // MARK: - Gestures

    /// « Autoriser » or « Refuser » on a sensitive action that waits.
    public func decide(_ review: VigieReview, allow: Bool) async {
        guard let pending = review.pendingID else { return }
        await send(review.id, hiding: true) { try await self.client.decide(pending: pending, allow: allow) }
    }

    /// « Répondre » to a question that waits: the answers go to Claude as a click in VS Code.
    public func answer(_ review: VigieReview, answers: [String: String]) async -> Bool {
        guard let pending = review.pendingID else { return false }
        return await send(review.id, hiding: true) { try await self.client.answer(pending: pending, answers: answers) }
    }

    /// « Ça me va » on a question Vigie answered for Paul.
    public func approve(_ review: VigieReview) async {
        guard let question = review.question else { return }
        await send(review.id, hiding: true) { try await self.client.approve(question: question.id) }
    }

    /// « Changer » a question Vigie answered for Paul: the engine writes the correction; it is copied, and the
    /// conversation opens, to paste it.
    public func change(_ review: VigieReview, answers: [String: String]) async -> Bool {
        guard let question = review.question else { return false }
        return await send(review.id, hiding: true) {
            let correction = try await self.client.change(question: question.id, answers: answers)
            if let text = correction.correction, !text.isEmpty { self.actions.copy(text) }
            if let link = correction.openURL.flatMap(URL.init(string:)) {
                self.actions.open(link)
            } else if let conversation = review.conversationID {
                _ = try? await self.client.open(conversation: conversation)
            }
            self.info = "Message copié : colle-le dans la conversation."
        }
    }

    /// Takes away what Paul has seen.
    public func dismiss(_ review: VigieReview) async {
        await send(review.id, hiding: true) { try await self.client.dismiss(review: review.id) }
    }

    /// Opens the conversation in VS Code; when only its folder opened, says where to find it.
    public func open(conversation id: String) async {
        await send("ouvrir:" + id) {
            let opening = try await self.client.open(conversation: id)
            if opening.opened == "folder", let message = opening.message { self.info = message }
        }
    }

    /// Terminal with the command typed, not run: a sudo command asks for Paul's password.
    public func runInTerminal(_ review: VigieReview) async {
        guard let command = review.command else { return }
        await send("terminal:" + review.id) {
            let opening = try await self.client.openTerminal(command: command, cwd: review.cwd, review: review.id)
            if opening.mode == "clipboard" { self.info = opening.message ?? "Commande copiée : colle-la dans Terminal." }
        }
    }

    /// Copies an action's command; a masked one is never copied (21/11: a key would leave with it).
    public func copy(_ review: VigieReview) {
        guard let command = review.command, !review.commandIsMasked else { return }
        actions.copy(command)
        info = "Commande copiée."
    }

    /// « Relancer » the engine, as the app Vigie's button: its agent restarted by macOS.
    public func restartEngine() async {
        guard !sending.contains("moteur") else { return }
        sending.insert("moteur")
        defer { sending.remove("moteur") }
        if await actions.restart() {
            problem = nil
            // The engine takes a few seconds to answer again.
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(1))
                await refresh()
                if link == .running { return }
            }
        } else {
            problem = "Le moteur de Vigie n'a pas pu être relancé."
        }
    }

    /// The app Vigie is gone (21/11, the migration; Paul's choice: « Les couper »): the engine's own updates would install
    /// it again with each new version of Vigie. hub turns them off, once, and says so; Paul turns them on again in
    /// Réglages › Vigie if he wants, and hub leaves them then.
    static let updatesTurnedOffKey = "vigie.updatesTurnedOff"

    private func turnOffUpdatesWithoutTheApp() async {
        guard !defaults.bool(forKey: Self.updatesTurnedOffKey), !actions.appInstalled() else { return }
        defaults.set(true, forKey: Self.updatesTurnedOffKey)
        await setAutoUpdate(false)
        if problem == nil { info = "L'app Vigie n'est plus sur ce Mac : hub a coupé les mises à jour du moteur, qui l'auraient réinstallée." }
    }

    /// Where the engine says the app Vigie is (`data/app.path`, written by its installer), else in Applications.
    nonisolated static func appIsInstalled(folder: URL = VigieEngine().folder) -> Bool {
        let noted = (try? String(contentsOf: folder.appending(path: "data/app.path"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let places = [noted, "/Applications/Vigie.app"].compactMap { $0 }.filter { !$0.isEmpty }
        return places.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - A conversation

    /// The conversation open in its page, in detail; `nil` while it loads.
    @Published public private(set) var detail: VigieConversationDetail?
    /// The engine keeps no detail past 48 hours.
    @Published public private(set) var detailGone = false
    private(set) var detailID: String?
    private var detailLoop: Task<Void, Never>?
    private var detailRead: Date?

    /// The page of a conversation is on screen: its detail read now, again as soon as it moves (every 4 s), else
    /// every 30 s — it weighs hundreds of kilobytes.
    public func watch(conversation id: String) {
        guard detailID != id || detailLoop == nil else { return }
        detailLoop?.cancel()
        if detailID != id {
            detail = nil
            detailGone = false
            detailRead = nil
        }
        detailID = id
        detailLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readDetail()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    public func stopWatching() {
        detailLoop?.cancel()
        detailLoop = nil
    }

    func readDetail(force: Bool = false) async {
        guard let id = detailID else { return }
        let moved = overview.conversations.first { $0.id == id }?.lastActivity != detail?.summary.lastActivity
        let stale = detailRead.map { Date().timeIntervalSince($0) > 30 } ?? true
        guard force || detail == nil || moved || stale else { return }
        do {
            let fresh = try await client.conversation(id)
            guard detailID == id else { return }
            detailRead = Date()
            detailGone = false
            if fresh != detail { detail = fresh }
        } catch VigieFailure.refused(404, _) {
            detailGone = true
        } catch {
            // Said by the « Vue d'ensemble »'s link.
        }
    }

    /// Moves a conversation to another account: at the end of its turn, or `now` — it is interrupted, and Paul writes
    /// to it to go on.
    public func switchAccount(_ conversation: String, to account: String, now: Bool) async {
        var changes: [String: Any] = ["accountId": account]
        if now { changes["now"] = true }
        let body = SendableBox(changes)
        await send("compte:" + conversation) {
            let answer = try await self.client.conversationSettings(conversation, body.value)
            if let message = answer?.message, !message.isEmpty { self.info = message }
        }
        await readDetail(force: true)
    }

    /// A conversation's own auto-accept: always, never, or as the general setting (`nil`).
    public func setAutoAccept(_ conversation: String, to value: Bool?) async {
        let body = SendableBox(["autoAccept": value.map { $0 as Any } ?? NSNull()])
        await send("auto:" + conversation) { _ = try await self.client.conversationSettings(conversation, body.value) }
        await readDetail(force: true)
    }

    /// The accounts a conversation can go on to: another one, its session not full, its week not full.
    public func freeAccounts(excluding id: String?) -> [VigieAccount] {
        overview.accounts.filter { $0.id != id && ($0.session?.percent ?? 0) < 95 && ($0.week?.percent ?? 0) < 100 }
    }

    // MARK: - Settings

    public func setAutoAccept(_ on: Bool) async { await setting(["autoAccept": on]) { $0.autoAccept = on } }
    public func setQuestionsAuto(_ on: Bool) async { await setting(["questionsAuto": on]) { $0.questionsAuto = on } }
    public func setQuestionWait(_ minutes: Int) async { await setting(["questionWaitMin": minutes]) { $0.questionWaitMinutes = minutes } }
    public func setAutoUpdate(_ on: Bool) async { await setting(["autoUpdate": on]) { $0.autoUpdate = on } }
    public func setStopForgotten(_ on: Bool) async { await setting(["stopForgotten": on]) { $0.stopForgotten = on } }
    public func setConnectorsDefault(_ on: Bool) async {
        await setting(["connectorsDefault": on ? "on" : "off"]) { $0.connectorsDefault = on ? "on" : "off" }
    }
    public func setSafeguards(_ on: Bool) async { await setting(["guard": ["enabled": on]]) { $0.safeguards.enabled = on } }
    public func setSafeguardWait(_ minutes: Int) async {
        await setting(["guard": ["waitMin": minutes]]) { $0.safeguards.waitMinutes = minutes }
    }
    public func setRule(_ id: String, on: Bool) async {
        await setting(["guard": ["rules": [["id": id, "disabled": !on]]]]) { settings in
            if let index = settings.safeguards.rules.firstIndex(where: { $0.id == id }) { settings.safeguards.rules[index].disabled = !on }
        }
    }

    /// A setting shown at once, sent, then read again: the engine's answer is what stays.
    private func setting(_ changes: [String: Any], _ apply: (inout VigieSettings) -> Void) async {
        guard var settings = overview.settings else { return }
        apply(&settings)
        overview.settings = settings
        let body = SendableBox(changes)
        await send("réglages") { _ = try await self.client.settings(body.value) }
    }

    // MARK: - Sending

    /// One at a time for the same thing: a second click while the first is on its way does nothing. `hiding`: the
    /// element goes from the page at once, back only if the engine refused.
    @discardableResult
    private func send(_ id: String, hiding: Bool = false, _ work: () async throws -> Void) async -> Bool {
        guard !sending.contains(id) else { return false }
        sending.insert(id)
        writes += 1
        if hiding { hidden[id] = Date() }
        defer { sending.remove(id) }
        var done = true
        do {
            try await work()
            problem = nil
        } catch {
            done = false
            if hiding { hidden[id] = nil }
            problem = Self.sentence(error)
        }
        writes += 1
        await refresh()
        return done
    }

    /// What went wrong, in French: the engine's own sentence when it gave one.
    static func sentence(_ error: any Error) -> String {
        switch error as? VigieFailure {
        case .absent: "Le moteur de Vigie n'est pas sur ce Mac."
        case .stopped: "Le moteur de Vigie ne répond pas."
        case .refused(_, let sentence?): sentence
        case .refused(401, nil): "Le moteur de Vigie ne reconnaît pas hub : relance-le depuis cette page."
        case .refused: "Le moteur de Vigie a refusé."
        case .unreadable, nil: "hub n'a pas compris la réponse de Vigie : l'un des deux est peut-être à mettre à jour."
        }
    }

    /// The engine's agent, as its installer names it.
    nonisolated static let engineAgent = "io.github.paulmailhes.vigie.engine"

    /// `launchctl kickstart -k gui/<uid>/<agent>`: what the app Vigie's « Relancer » ran.
    nonisolated static func kickstart() async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(engineAgent)"]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

/// A body of settings, built on the main actor and sent from it: nothing else touches it.
private struct SendableBox: @unchecked Sendable {
    let value: [String: Any]

    init(_ value: [String: Any]) {
        self.value = value
    }
}
