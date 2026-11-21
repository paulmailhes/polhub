import AppKit
import Foundation
import SwiftUI
import Testing
import VigieKit
@testable import MeetingsUI

/// 21/11 : Vigie dans hub, première étape. Ce qui attend Paul, ses conversations, et l'état du moteur dit en clair. Un
/// faux moteur répond : jamais le vrai, jamais son jeton. Données inventées.
@MainActor @Suite struct VigieLibraryTests {
    final class Engine: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [(Int, String)] = []
        private var seen: [URLRequest] = []
        var down = false

        func answer(_ body: String, status: Int = 200) { lock.withLock { answers.append((status, body)) } }
        /// The answers from now on, in this order, the last one staying.
        func next(_ list: [(String, Int)]) { lock.withLock { answers = list.map { ($0.1, $0.0) } } }
        var requests: [URLRequest] { lock.withLock { seen } }

        func respond(_ request: URLRequest) throws -> (Data, URLResponse) {
            try lock.withLock {
                seen.append(request)
                if down { throw URLError(.cannotConnectToHost) }
                // The last answer stays for the requests that follow.
                let (status, body) = answers.count > 1 ? answers.removeFirst() : answers.first ?? (200, "{}")
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        }
    }

    static let overview = """
    { "toReview": [
        { "id": "g:b1b9:1", "kind": "blocked", "state": "waiting", "pendingId": "91234", "rule": "Envoi forcé (git push --force)",
          "command": "git push --force origin main", "conversationId": "b1b9", "conversationTitle": "Refaire le site", "title": "Écrase l'historique du dépôt" },
        { "id": "q:7f3a", "kind": "question", "conversationId": "c2", "conversationTitle": "Facture de mars", "title": "Quel fond pour la charte ?",
          "detail": "Claude a pris « Fond B (recommandé) »", "question": { "id": "7f3a", "items": [ { "question": "Quel fond ?", "chosen": "Fond B" } ] } },
        { "id": "l:b1b9:2", "kind": "limit", "title": "Limite de session atteinte sur Travail 1" },
        { "id": "s:c2:3", "kind": "notice", "title": "Compte changé : envoie un message pour relancer" } ],
      "conversations": [
        { "id": "b1b9", "title": "Refaire le site", "project": "atelier", "status": "blocked", "running": true, "accountId": "travail1", "needsYou": 1,
          "headline": "Étape 4 sur 9 : la page d'accueil", "agentsRunning": 0 },
        { "id": "c2", "title": "Facture de mars", "project": "compta", "status": "working", "running": true, "accountId": "perso", "agentsRunning": 2 },
        { "id": "c3", "title": "Ancienne", "status": "closed" } ],
      "accounts": [ { "id": "travail1", "label": "Travail 1" }, { "id": "perso", "label": "Perso" } ],
      "settings": { "autoAccept": true, "questionsAuto": true, "questionWaitMin": 20, "autoUpdate": true, "stopForgotten": true, "connectorsDefault": "off",
                    "guard": { "enabled": true, "waitMin": 10, "rules": [ { "id": "sudo", "label": "Commande administrateur (sudo)" },
                                                                          { "id": "push-force", "label": "Envoi forcé (git push --force)" } ] } } }
    """

    /// What the library did outside hub: copied, opened, restarted.
    final class Outside {
        var copied: [String] = []
        var opened: [URL] = []
        var restarts = 0
        var restartWorks = true
    }

    func library(token: Bool = true, outside: Outside = Outside()) throws -> (VigieLibrary, Engine) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-ui-\(UUID().uuidString)")
        if token {
            try FileManager.default.createDirectory(at: folder.appending(path: "data"), withIntermediateDirectories: true)
            try Data("jeton-d-essai".utf8).write(to: folder.appending(path: "data/api-token"))
        }
        let engine = Engine()
        let client = VigieClient(engine: VigieEngine(folder: folder)) { request in try engine.respond(request) }
        let actions = VigieLibrary.Actions(copy: { outside.copied.append($0) }, open: { outside.opened.append($0) },
                                           restart: { outside.restarts += 1; return outside.restartWorks })
        return (VigieLibrary(client: client, actions: actions), engine)
    }

    @Test func whatWaitsIsApartFromWhatIsOnlyToSee() async throws {
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        #expect(library.link == .running)
        #expect(library.decisions.map(\.id) == ["g:b1b9:1"] && library.toRead.map(\.id) == ["q:7f3a"])
        #expect(library.toSee.map(\.id) == ["l:b1b9:2", "s:c2:3"])
        #expect(library.openConversations.map(\.title) == ["Refaire le site", "Facture de mars"] && library.closedCount == 1)
        #expect(VigieWords.status(library.openConversations[0]) == "attend ta décision" && VigieWords.needsPaul(library.openConversations[0]))
        #expect(VigieWords.status(library.openConversations[1]) == "travaille · 2 agents" && !VigieWords.needsPaul(library.openConversations[1]))
        #expect(VigieWords.context(library.decisions[0]) == "Refaire le site · Envoi forcé (git push --force)")
        #expect(VigieWords.canDismiss(library.toSee[1]) && VigieWords.canDismiss(library.toSee[0]))
        #expect(VigieWords.gesture(library.decisions[0]) == .decide(sudo: false))
        #expect(VigieWords.chosen(library.toRead[0]) == "Claude a pris « Fond B »")
    }

    @Test func theEnginesStateIsSaidPlainly() async throws {
        let (absent, untouched) = try library(token: false)
        await absent.refresh()
        #expect(absent.link == .absent && untouched.requests.isEmpty)
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        engine.down = true
        // One read missed is not a stopped engine; two are.
        await library.refresh()
        #expect(library.link == .running)
        await library.refresh()
        // Stopped: what was read last stays on screen.
        #expect(library.link == .stopped && library.openConversations.count == 2)
        engine.down = false
        engine.next([(#"{"ok":false}"#, 401)])
        await library.refresh()
        #expect(library.link == .trouble("Le moteur de Vigie ne reconnaît pas hub : relance-le depuis cette page."))
    }

    @Test func aDecisionIsSentOnceThenTheOverviewIsReadAgain() async throws {
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        let review = library.decisions[0]
        await library.decide(review, allow: true)
        let paths = engine.requests.map { $0.url?.path() ?? "" }
        #expect(paths == ["/api/v2/overview", "/api/v2/pending/91234", "/api/v2/overview"])
        #expect(library.problem == nil && library.sending.isEmpty)
        // The engine still lists it (its read was older): it stays away from the page.
        #expect(library.decisions.isEmpty)
        await library.approve(library.toRead[0])
        await library.dismiss(library.toSee[1])
        await library.open(conversation: "c2")
        let posts = engine.requests.filter { $0.httpMethod == "POST" }.map { $0.url?.path() ?? "" }
        #expect(posts == ["/api/v2/pending/91234", "/api/v2/questions/7f3a/review", "/api/v2/review/s:c2:3/dismiss", "/api/v2/open"])
    }

    @Test func aRefusedGestureSaysWhyInTheEnginesWords() async throws {
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        let review = library.decisions[0]
        engine.next([(#"{"ok":false,"error":"Cette attente est finie."}"#, 404), (Self.overview, 200)])
        await library.decide(review, allow: false)
        // Refused: it comes back, with the engine's sentence.
        #expect(library.problem == "Cette attente est finie." && library.link == .running && library.decisions.map(\.id) == ["g:b1b9:1"])
    }

    /// 21/11, the migration: everything the app Vigie did on its page is done from hub.
    @Test func answerChangeTerminalAndRestartWorkFromHub() async throws {
        let outside = Outside()
        let (library, engine) = try library(outside: outside)
        let waiting = """
        { "toReview": [ { "id": "w:b1b9:5", "kind": "waiting", "conversationId": "b1b9", "title": "Quelle base ?", "pendingId": "4242",
                          "questions": [ { "question": "Quelle base ?", "options": [ { "label": "Postgres" }, { "label": "SQLite" } ] } ] },
                        { "id": "g:b1b9:1", "kind": "blocked", "state": "waiting", "pendingId": "77", "needsPassword": true,
                          "command": "sudo make install", "cwd": "/Users/alex/Code/atelier", "title": "Installe" },
                        { "id": "q:7f3a", "kind": "question", "conversationId": "b1b9", "title": "Quel fond ?",
                          "question": { "id": "7f3a", "items": [ { "question": "Quel fond ?", "options": [ { "label": "Fond A" }, { "label": "Fond B" } ],
                                                                   "chosen": "Fond B" } ] } } ],
          "settings": { "autoAccept": true, "guard": { "enabled": true, "waitMin": 10, "rules": [ { "id": "sudo", "label": "sudo" } ] } } }
        """
        engine.answer(waiting)
        await library.refresh()
        // Neither has a deadline: the engine's order.
        #expect(VigieWords.gesture(library.decisions[0]) == .answer && VigieWords.gesture(library.decisions[1]) == .decide(sudo: true))
        let answered = await library.answer(library.decisions[0], answers: ["Quelle base ?": "SQLite"])
        #expect(answered)
        engine.next([(#"{"ok":true,"correction":"Prends le fond A.","openUrl":"vscode://anthropic.claude-code/open?session=b1b9"}"#, 200), (waiting, 200)])
        let changed = await library.change(library.toRead[0], answers: ["Quel fond ?": "Fond A"])
        #expect(changed && outside.copied == ["Prends le fond A."] && outside.opened.map(\.absoluteString) == ["vscode://anthropic.claude-code/open?session=b1b9"])
        #expect(library.info == "Message copié : colle-le dans la conversation.")
        engine.next([(#"{"ok":true,"mode":"typed"}"#, 200), (waiting, 200)])
        await library.runInTerminal(library.decisions[0])
        await library.setAutoAccept(false)
        await library.setRule("sudo", on: false)
        let posts = engine.requests.filter { $0.httpMethod == "POST" }
        #expect(posts.map { $0.url?.path() ?? "" } == ["/api/v2/pending/4242", "/api/v2/questions/7f3a/review", "/api/v2/open",
                                                       "/api/v2/settings", "/api/v2/settings"])
        let last = try #require(JSONSerialization.jsonObject(with: posts[4].httpBody ?? Data()) as? NSDictionary)
        #expect(last == ["guard": ["rules": [["id": "sudo", "disabled": true]]]] as NSDictionary)
        // A masked command is never copied.
        library.copy(VigieReview(id: "g:x", kind: .blocked, title: "", command: "deploy --token ••••"))
        #expect(outside.copied == ["Prends le fond A."])
        await library.restartEngine()
        #expect(outside.restarts == 1 && library.link == .running)
    }

    /// `HUB_LIVE=1 HUB_SNAPSHOTS=<dossier> swift test --filter VigieLibraryTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUB_LIVE"] == "1")) func thePageInCapture() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        try await LiveWindow.capture(VigiePage(library: library), to: folder.appending(path: "vigie-vue-d-ensemble.png"),
                                     size: NSSize(width: 900, height: 1_100), wait: .milliseconds(1_000))
        try await LiveWindow.capture(VigieSettingsPane(library: library), to: folder.appending(path: "vigie-reglages.png"),
                                     size: NSSize(width: 720, height: 760), wait: .milliseconds(900))
        let (absent, _) = try self.library(token: false)
        await absent.refresh()
        try await LiveWindow.capture(VigiePage(library: absent), to: folder.appending(path: "vigie-absent.png"),
                                     size: NSSize(width: 900, height: 320), wait: .milliseconds(800))
    }
}
