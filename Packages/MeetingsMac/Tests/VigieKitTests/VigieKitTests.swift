import Foundation
import Testing
@testable import VigieKit

/// 21/11 : Vigie dans hub. Ce que dit son moteur est lu même s'il manque des champs ; hub ne lui parle que sur ce Mac,
/// avec son jeton d'accès, et une écriture porte les deux en-têtes qu'il exige. Données inventées.
@Suite struct VigieOverviewTests {
    static let sample = """
    {
      "now": "2026-10-20T00:30:00.000Z",
      "toReview": [
        { "id": "g:b1b9:1", "kind": "blocked", "state": "waiting", "pendingId": "91234", "expiresAt": "2026-10-20T00:40:00.000Z",
          "rule": "Commande administrateur (sudo)", "command": "sudo rm -rf /tmp/essai", "conversationId": "b1b9", "conversationTitle": "Atelier",
          "title": "Supprime un dossier", "needsPassword": true, "ts": "2026-10-20T00:29:00.000Z" },
        { "id": "q:7f3a", "kind": "question", "conversationId": "b1b9", "conversationTitle": "Atelier", "title": "Quel fond pour la charte ?",
          "detail": "Claude a pris « Fond B (recommandé) »", "ts": "2026-10-20T00:20:00Z",
          "question": { "id": "7f3a", "items": [ { "question": "Quel fond pour la charte ?", "header": "Fond", "multiSelect": false,
                        "options": [ { "label": "Fond B (recommandé)" } ], "chosen": "Fond B (recommandé)" } ] } },
        { "id": "l:b1b9:2", "kind": "limit", "title": "Limite de session atteinte sur Travail 1" },
        { "id": "x:1", "kind": "une-sorte-nouvelle", "title": "Plus tard" },
        { "kind": "sans-identifiant" }
      ],
      "conversations": [
        { "id": "b1b9", "title": "Refaire le site Horizon complet", "project": "atelier", "cwd": "/Users/alex/Code/atelier", "status": "working",
          "running": true, "accountId": "travail1", "agentsRunning": 2, "lastActivity": "2026-10-20T00:25:31.000Z", "needsYou": 2,
          "headline": "Étape L2.24 sur L2.29", "progress": { "done": 23, "total": 31, "label": "Plan 1.4" } },
        { "id": "c2", "status": "dans-le-futur" }
      ],
      "accounts": [ { "id": "travail1", "label": "Travail 1", "email": "alex@studio-exemple.fr", "connected": true } ],
      "engine": { "indexing": false }
    }
    """

    @Test func theOverviewIsReadWithWhatTheEngineGives() throws {
        let overview = try JSONDecoder().decode(VigieOverview.self, from: Data(Self.sample.utf8))
        // The element without an identifier is left out; the others stay.
        #expect(overview.toReview.map(\.id) == ["g:b1b9:1", "q:7f3a", "l:b1b9:2", "x:1"])
        let blocked = overview.toReview[0]
        #expect(blocked.kind == .blocked && blocked.isPendingDecision && blocked.isDecision && blocked.needsPaul && blocked.needsPassword)
        #expect(blocked.pendingID == "91234" && blocked.command == "sudo rm -rf /tmp/essai" && blocked.rule == "Commande administrateur (sudo)")
        #expect(blocked.expiresAt == VigieDate.parse("2026-10-20T00:40:00.000Z") && blocked.expiresAt != nil)
        let question = overview.toReview[1]
        #expect(question.kind == .question && question.needsPaul && !question.isPendingDecision)
        #expect(question.question?.id == "7f3a" && question.question?.items.first?.chosen == ["Fond B (recommandé)"] && !question.isDecision)
        #expect(question.at == VigieDate.parse("2026-10-20T00:20:00Z") && question.at != nil)
        #expect(overview.toReview[2].kind == .limit && !overview.toReview[2].needsPaul)
        #expect(overview.toReview[3].kind == .other && !overview.toReview[3].needsPaul)
        let conversation = overview.conversations[0]
        #expect(conversation.title == "Refaire le site Horizon complet" && conversation.status == .working && conversation.running)
        #expect(conversation.needsYou == 2 && conversation.headline == "Étape L2.24 sur L2.29" && conversation.progress == .init(done: 23, total: 31))
        #expect(overview.conversations[1].status == .other && overview.conversations[1].title.isEmpty)
        #expect(overview.accountLabel("travail1") == "Travail 1" && overview.accountLabel("autre") == nil && overview.accountLabel(nil) == nil)
    }

    /// 21/11, the migration (Paul : « complètement désactiver mon Vigie, utiliser celui de Hub ») : what waits is
    /// counted as Vigie counts it, the soonest refusal first; the questions answered for Paul are to read again; Codex
    /// stays out; the settings and the engine's sentences are read.
    static let full = """
    {
      "settings": { "autoAccept": false, "questionsAuto": true, "questionWaitMin": 10, "connectorsDefault": "off", "autoUpdate": true,
                    "stopForgotten": true, "guard": { "enabled": true, "waitMin": 5,
                    "rules": [ { "id": "sudo", "label": "Commande administrateur (sudo)", "disabled": false }, { "id": "push-force", "disabled": true } ] } },
      "toReview": [
        { "id": "c:b1b9", "kind": "waiting", "conversationId": "b1b9", "title": "Attend ta réponse dans VS Code", "ts": "2026-10-20T00:10:00Z" },
        { "id": "w:b1b9:5", "kind": "waiting", "conversationId": "b1b9", "title": "Quelle base ?", "pendingId": 4242, "ts": "2026-10-20T00:20:00Z",
          "questions": [ { "question": "Quelle base ?", "header": "Base", "multiSelect": false,
                           "options": [ { "label": "Postgres", "description": "La même qu'avant" }, { "label": "SQLite" } ] } ] },
        { "id": "g:b1b9:9", "kind": "blocked", "state": "waiting", "pendingId": "9", "expiresAt": "2026-10-20T00:50:00Z", "title": "Plus tard" },
        { "id": "g:b1b9:8", "kind": "blocked", "state": "waiting", "pendingId": "8", "expiresAt": "2026-10-20T00:35:00Z", "title": "Bientôt",
          "command": "deploy --token ••••", "cwd": "/Users/alex/Code/atelier", "byAgent": "faire:L2" },
        { "id": "q:7f3a", "kind": "question", "title": "Quel fond ?", "question": { "id": "7f3a",
          "items": [ { "question": "Quels écrans ?", "multiSelect": true, "options": [ { "label": "Accueil" }, { "label": "Profil" } ],
                       "chosen": ["Accueil", "Profil"] } ] } },
        { "id": "b:b1b9:2", "kind": "blocked", "state": "blocked", "reason": "delai", "title": "Refusée faute de réponse" },
        { "id": "l:b1b9:3", "kind": "limit", "title": "Limite de session atteinte sur Travail 1", "accountId": "travail1", "scope": "session",
          "resetsAt": "2026-10-20T03:40:00Z" },
        { "id": "v:ab12", "kind": "blocked", "state": "awaiting", "title": "Codex" },
        { "id": "codex-hook", "kind": "notice", "title": "Module à accepter dans Codex" },
        { "id": "g:cx1:1", "kind": "blocked", "state": "waiting", "pendingId": "77", "conversationId": "cx1", "title": "Codex aussi" }
      ],
      "conversations": [ { "id": "b1b9", "title": "Atelier", "cwd": "/Users/alex/Code/atelier" },
                         { "id": "cx1", "title": "Dans Codex", "agent": "codex" } ],
      "accounts": [ { "id": "travail1", "label": "Travail 1" }, { "id": "codex", "label": "Codex", "kind": "codex" } ],
      "engine": { "notices": [ "Connexion de Travail 1 remise par Vigie à 10:12.", { "text": "Dossier de Perso réparé." }, { "rien": 1 } ] }
    }
    """

    @Test func whatWaitsIsCountedAsVigieCountsIt() throws {
        let overview = try JSONDecoder().decode(VigieOverview.self, from: Data(Self.full.utf8))
        // The soonest refusal first, then the longest wait.
        #expect(overview.decisions.map(\.id) == ["g:b1b9:8", "g:b1b9:9", "c:b1b9", "w:b1b9:5"])
        #expect(overview.toRead.map(\.id) == ["q:7f3a"])
        #expect(overview.toSee.map(\.id) == ["b:b1b9:2", "l:b1b9:3"])
        // Codex's conversation, account and what it asks stay out.
        #expect(overview.conversations.map(\.id) == ["b1b9"] && overview.accounts.map(\.id) == ["travail1"])
        #expect(overview.notices == ["Connexion de Travail 1 remise par Vigie à 10:12.", "Dossier de Perso réparé."])
        let question = try #require(overview.decisions.last)
        #expect(question.canAnswer && question.pendingID == "4242" && question.questions.first?.options.map(\.label) == ["Postgres", "SQLite"])
        #expect(question.questions.first?.header == "Base" && question.questions.first?.options.first?.description == "La même qu'avant")
        let masked = overview.decisions[0]
        #expect(masked.commandIsMasked && masked.cwd == "/Users/alex/Code/atelier" && masked.byAgent == "faire:L2")
        let answered = try #require(overview.toRead.first?.question?.items.first)
        #expect(answered.multiSelect && answered.chosen == ["Accueil", "Profil"] && answered.chosenText == "Accueil, Profil")
        let limit = overview.toSee[1]
        #expect(limit.accountID == "travail1" && limit.scope == "session" && limit.resetsAt != nil)
        #expect(overview.toSee[0].reason == "delai")
        let settings = try #require(overview.settings)
        #expect(!settings.autoAccept && settings.questionsAuto && settings.questionWaitMinutes == 10 && settings.autoUpdate == true)
        #expect(settings.stopForgotten == true && settings.connectorsDefault == "off")
        #expect(settings.safeguards.enabled && settings.safeguards.waitMinutes == 5)
        #expect(settings.safeguards.rules.map(\.label) == ["Commande administrateur (sudo)", "push-force"] && settings.safeguards.rules[1].disabled)
    }

    @Test func anEmptyAnswerIsAnEmptyOverview() throws {
        #expect(try JSONDecoder().decode(VigieOverview.self, from: Data("{}".utf8)) == VigieOverview())
    }
}

@Suite struct VigieClientTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        func add(_ request: URLRequest) { lock.withLock { requests.append(request) } }
        var all: [URLRequest] { lock.withLock { requests } }
    }

    /// An engine's folder with a token in it, and a client that answers `status` with `body`.
    func client(status: Int = 200, body: String = "{}", token: String? = "jeton-d-essai") throws -> (VigieClient, Calls) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-\(UUID().uuidString)")
        if let token {
            try FileManager.default.createDirectory(at: folder.appending(path: "data"), withIntermediateDirectories: true)
            try Data((token + "\n").utf8).write(to: folder.appending(path: "data/api-token"))
        }
        let calls = Calls()
        let client = VigieClient(engine: VigieEngine(folder: folder)) { request in
            calls.add(request)
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        return (client, calls)
    }

    @Test func aReadCarriesTheTokenAndStaysOnThisMac() async throws {
        let (client, calls) = try client(body: VigieOverviewTests.sample)
        let overview = try await client.overview()
        #expect(overview.conversations.count == 2)
        let request = try #require(calls.all.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:4777/api/v2/overview" && request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-Vigie-Token") == "jeton-d-essai")
        #expect(request.value(forHTTPHeaderField: "X-Vigie") == nil && request.httpBody == nil)
    }

    @Test func aWriteCarriesTheTwoHeadersTheEngineAsksFor() async throws {
        let (client, calls) = try client(body: #"{"ok":true}"#)
        try await client.decide(pending: "91234", allow: true)
        try await client.decide(pending: "91234", allow: false)
        try await client.approve(question: "7f3a")
        try await client.dismiss(review: "s:b1b9:3")
        try await client.open(conversation: "b1b9")
        let requests = calls.all
        #expect(requests.map { $0.url?.path() } == ["/api/v2/pending/91234", "/api/v2/pending/91234", "/api/v2/questions/7f3a/review",
                                                    "/api/v2/review/s:b1b9:3/dismiss", "/api/v2/open"])
        #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "X-Vigie") == "1"
            && $0.value(forHTTPHeaderField: "Content-Type") == "application/json" && $0.value(forHTTPHeaderField: "X-Vigie-Token") == "jeton-d-essai" })
        let bodies = try requests.map { try JSONDecoder().decode([String: String].self, from: try #require($0.httpBody)) }
        #expect(bodies == [["decision": "allow"], ["decision": "deny"], ["action": "ok"], [:], ["kind": "conversation", "id": "b1b9"]])
    }

    /// The answers, the change, Terminal and the settings carry what the engine expects; opening VS Code waits long.
    @Test func theNewWritesCarryWhatTheEngineExpects() async throws {
        let (client, calls) = try client(body: #"{"ok":true,"correction":"Prends SQLite.","openUrl":"vscode://anthropic.claude-code/open?session=b1b9","settings":{"autoAccept":false}}"#)
        try await client.answer(pending: "4242", answers: ["Quelle base ?": "SQLite"])
        let correction = try await client.change(question: "7f3a", answers: ["Quel fond ?": "Fond A"])
        try await client.openTerminal(command: "sudo make install", cwd: "/Users/alex/Code/atelier", review: "g:b1b9:8")
        let settings = try await client.settings(["autoAccept": false, "guard": ["waitMin": 10]])
        try await client.open(conversation: "b1b9")
        #expect(correction.correction == "Prends SQLite." && correction.openURL == "vscode://anthropic.claude-code/open?session=b1b9")
        #expect(settings?.autoAccept == false)
        let requests = calls.all
        let bodies = requests.map { (try? JSONSerialization.jsonObject(with: $0.httpBody ?? Data())) as? NSDictionary ?? [:] }
        #expect(bodies[0] == ["answers": ["Quelle base ?": "SQLite"]] as NSDictionary)
        #expect(bodies[1] == ["action": "change", "answers": ["Quel fond ?": "Fond A"]] as NSDictionary)
        #expect(bodies[2] == ["kind": "terminal", "command": "sudo make install", "cwd": "/Users/alex/Code/atelier", "id": "g:b1b9:8"] as NSDictionary)
        #expect(bodies[3] == ["autoAccept": false, "guard": ["waitMin": 10]] as NSDictionary)
        #expect(requests.map(\.timeoutInterval) == [30, 30, 90, 30, 90])
    }

    @Test func withoutTheEngineNothingIsAsked() async throws {
        let (client, calls) = try client(token: nil)
        await #expect(throws: VigieFailure.absent) { try await client.overview() }
        #expect(calls.all.isEmpty && !client.engine.isInstalled)
    }

    @Test func aRefusalKeepsTheEnginesOwnSentence() async throws {
        let (client, _) = try client(status: 404, body: #"{"ok":false,"error":"Cette attente est finie."}"#)
        await #expect(throws: VigieFailure.refused(404, "Cette attente est finie.")) { try await client.decide(pending: "1", allow: true) }
        let (unreadable, _) = try self.client(body: "pas du JSON")
        await #expect(throws: VigieFailure.unreadable) { try await unreadable.overview() }
    }

    @Test func anEngineThatDoesNotAnswerIsStopped() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "data"), withIntermediateDirectories: true)
        try Data("jeton".utf8).write(to: folder.appending(path: "data/api-token"))
        let client = VigieClient(engine: VigieEngine(folder: folder)) { _ in throw URLError(.cannotConnectToHost) }
        await #expect(throws: VigieFailure.stopped) { try await client.overview() }
        #expect(await client.isRunning() == false)
    }
}
