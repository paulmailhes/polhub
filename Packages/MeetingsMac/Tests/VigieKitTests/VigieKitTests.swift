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
        #expect(blocked.kind == .blocked && blocked.isPendingDecision && blocked.needsPaul && blocked.needsPassword)
        #expect(blocked.pendingID == "91234" && blocked.command == "sudo rm -rf /tmp/essai" && blocked.rule == "Commande administrateur (sudo)")
        #expect(blocked.expiresAt == VigieDate.parse("2026-10-20T00:40:00.000Z") && blocked.expiresAt != nil)
        let question = overview.toReview[1]
        #expect(question.kind == .question && question.needsPaul && !question.isPendingDecision)
        #expect(question.question?.id == "7f3a" && question.question?.items.first?.chosen == "Fond B (recommandé)")
        #expect(question.at == VigieDate.parse("2026-10-20T00:20:00Z") && question.at != nil)
        #expect(overview.toReview[2].kind == .limit && !overview.toReview[2].needsPaul)
        #expect(overview.toReview[3].kind == .other && !overview.toReview[3].needsPaul)
        let conversation = overview.conversations[0]
        #expect(conversation.title == "Refaire le site Horizon complet" && conversation.status == .working && conversation.running)
        #expect(conversation.needsYou == 2 && conversation.headline == "Étape L2.24 sur L2.29" && conversation.progress == .init(done: 23, total: 31))
        #expect(overview.conversations[1].status == .other && overview.conversations[1].title.isEmpty)
        #expect(overview.accountLabel("travail1") == "Travail 1" && overview.accountLabel("autre") == nil && overview.accountLabel(nil) == nil)
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
