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
      "accounts": [ { "id": "travail1", "label": "Travail 1" }, { "id": "perso", "label": "Perso" } ] }
    """

    func library(token: Bool = true) throws -> (VigieLibrary, Engine) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-ui-\(UUID().uuidString)")
        if token {
            try FileManager.default.createDirectory(at: folder.appending(path: "data"), withIntermediateDirectories: true)
            try Data("jeton-d-essai".utf8).write(to: folder.appending(path: "data/api-token"))
        }
        let engine = Engine()
        let client = VigieClient(engine: VigieEngine(folder: folder)) { request in try engine.respond(request) }
        return (VigieLibrary(client: client), engine)
    }

    @Test func whatWaitsIsApartFromWhatIsOnlyToSee() async throws {
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        #expect(library.link == .running)
        #expect(library.waiting.map(\.id) == ["g:b1b9:1", "q:7f3a"] && library.notices.map(\.id) == ["l:b1b9:2", "s:c2:3"])
        #expect(library.openConversations.map(\.title) == ["Refaire le site", "Facture de mars"] && library.closedCount == 1)
        #expect(VigieWords.status(library.openConversations[0]) == "attend ta décision" && VigieWords.needsPaul(library.openConversations[0]))
        #expect(VigieWords.status(library.openConversations[1]) == "travaille · 2 agents" && !VigieWords.needsPaul(library.openConversations[1]))
        #expect(VigieWords.context(library.waiting[0]) == "Refaire le site · Envoi forcé (git push --force)")
        #expect(VigieWords.canDismiss(library.notices[1]) && !VigieWords.canDismiss(library.notices[0]))
    }

    @Test func theEnginesStateIsSaidPlainly() async throws {
        let (absent, untouched) = try library(token: false)
        await absent.refresh()
        #expect(absent.link == .absent && untouched.requests.isEmpty)
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        engine.down = true
        await library.refresh()
        // Stopped: what was read last stays on screen.
        #expect(library.link == .stopped && library.openConversations.count == 2)
        engine.down = false
        engine.next([(#"{"ok":false}"#, 401)])
        await library.refresh()
        #expect(library.link == .trouble("Le moteur de Vigie ne reconnaît pas hub : rouvre l'app Vigie."))
    }

    @Test func aDecisionIsSentOnceThenTheOverviewIsReadAgain() async throws {
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        let review = library.waiting[0]
        await library.decide(review, allow: true)
        let paths = engine.requests.map { $0.url?.path() ?? "" }
        #expect(paths == ["/api/v2/overview", "/api/v2/pending/91234", "/api/v2/overview"])
        #expect(library.problem == nil && library.sending.isEmpty)
        await library.approve(library.waiting[1])
        await library.dismiss(library.notices[1])
        await library.open(conversation: "c2")
        let posts = engine.requests.filter { $0.httpMethod == "POST" }.map { $0.url?.path() ?? "" }
        #expect(posts == ["/api/v2/pending/91234", "/api/v2/questions/7f3a/review", "/api/v2/review/s:c2:3/dismiss", "/api/v2/open"])
    }

    @Test func aRefusedGestureSaysWhyInTheEnginesWords() async throws {
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        let review = library.waiting[0]
        engine.next([(#"{"ok":false,"error":"Cette attente est finie."}"#, 404), (Self.overview, 200)])
        await library.decide(review, allow: false)
        #expect(library.problem == "Cette attente est finie." && library.link == .running)
    }

    /// `HUB_LIVE=1 HUB_SNAPSHOTS=<dossier> swift test --filter VigieLibraryTests`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HUB_LIVE"] == "1")) func thePageInCapture() async throws {
        let folder = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["HUB_SNAPSHOTS"]), isDirectory: true)
        let (library, engine) = try library()
        engine.answer(Self.overview)
        await library.refresh()
        try await LiveWindow.capture(VigiePage(library: library), to: folder.appending(path: "vigie-vue-d-ensemble.png"),
                                     size: NSSize(width: 900, height: 900), wait: .milliseconds(1_000))
        let (absent, _) = try self.library(token: false)
        await absent.refresh()
        try await LiveWindow.capture(VigiePage(library: absent), to: folder.appending(path: "vigie-absent.png"),
                                     size: NSSize(width: 900, height: 320), wait: .milliseconds(800))
    }
}
