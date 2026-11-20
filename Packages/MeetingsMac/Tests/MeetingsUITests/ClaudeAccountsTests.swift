import Foundation
import Testing
@testable import MeetingsUI

/// « Comptes Claude » on the Accueil (0.36.0, 18/11): the use of each account, read from Vigie on this Mac with a read
/// token of its own; nothing at all when Vigie is not there. Every account and token here is invented.
@Suite(.timeLimit(.minutes(1))) struct ClaudeAccountsTests {
    /// A Vigie that answers what it is told, and remembers what it was asked.
    final class FakeVigie: @unchecked Sendable {
        private let lock = NSLock()
        private var answers: [(Data, Int)]
        private(set) var requests: [URLRequest] = []
        var onRequest: (Int) -> Void = { _ in }

        init(_ answers: [(Data, Int)]) {
            self.answers = answers
        }

        var fetch: VigieAccountsReader.Fetch {
            { [self] request in
                let (index, answer): (Int, (Data, Int)) = lock.withLock {
                    requests.append(request)
                    return (requests.count, answers.count > 1 ? answers.removeFirst() : answers.first ?? (Data(), 500))
                }
                onRequest(index)
                return answer
            }
        }

        var count: Int { lock.withLock { requests.count } }
    }

    static let tokenA = String(repeating: "a1", count: 32)
    static let tokenB = String(repeating: "b2", count: 32)

    static let answer = Data("""
    {"accounts":[
     {"id":"travail","label":"Travail","isDefault":true,"connected":true,
      "usage":{"session":{"pct":20,"resetsAt":"2026-11-18T22:40:00.000Z"},
               "week":{"pct":71,"resetsAt":"2026-11-23T19:00:00.000Z","fullAt":"2026-11-19T13:00:00.000Z"},
               "weekModel":null,"observedAt":"2026-11-18T21:30:00.000Z","source":"session"}},
     {"id":"perso","label":"Perso","isDefault":false,"connected":true,
      "usage":{"session":null,"week":{"pct":12,"resetsAt":"2026-11-23T19:00:00Z","fullAt":null},"weekModel":null,
               "observedAt":"2026-11-18T21:00:00.000Z","source":"ping"}},
     {"id":"ancien","label":"Ancien","isDefault":false,"connected":false,"usage":null}
    ]}
    """.utf8)

    func tokenFile(_ token: String?) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vigie-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "read-token")
        if let token { try Data("\(token)\n".utf8).write(to: file) }
        return file
    }

    // MARK: - The reader

    @Test func noTokenNoRequest() async throws {
        let vigie = FakeVigie([(Self.answer, 200)])
        #expect(await VigieAccountsReader(tokenFile: try tokenFile(nil), fetch: vigie.fetch).accounts() == nil)
        // A file that is not a token is none either.
        #expect(await VigieAccountsReader(tokenFile: try tokenFile("pas un jeton"), fetch: vigie.fetch).accounts() == nil)
        #expect(vigie.count == 0)
    }

    @Test func readsAndKeepsConnected() async throws {
        let vigie = FakeVigie([(Self.answer, 200)])
        let accounts = await VigieAccountsReader(tokenFile: try tokenFile(Self.tokenA), fetch: vigie.fetch).accounts()
        #expect(accounts?.map(\.label) == ["Travail", "Perso"])
        let request = try #require(vigie.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "http://127.0.0.1:4777/api/v2/accounts")
        #expect(request.value(forHTTPHeaderField: "X-Vigie-Read-Token") == Self.tokenA)
        #expect(request.value(forHTTPHeaderField: "X-Vigie-Token") == nil)
        #expect(accounts?.first?.usage?.week?.fullAt != nil)
    }

    /// Review Focus 4: a refusal reads the token again once, never in a loop.
    @Test func aRefusalRereadsTheTokenOnce() async throws {
        let file = try tokenFile(Self.tokenA)
        let renewed = FakeVigie([(Data(), 401), (Self.answer, 200)])
        renewed.onRequest = { index in if index == 1 { try? Data("\(Self.tokenB)\n".utf8).write(to: file) } }
        #expect(await VigieAccountsReader(tokenFile: file, fetch: renewed.fetch).accounts() != nil)
        #expect(renewed.count == 2 && renewed.requests.last?.value(forHTTPHeaderField: "X-Vigie-Read-Token") == Self.tokenB)

        let refused = FakeVigie([(Data(), 403)])
        #expect(await VigieAccountsReader(tokenFile: try tokenFile(Self.tokenA), fetch: refused.fetch).accounts() == nil)
        #expect(refused.count == 1)
    }

    @Test func garbageHidesTheSection() async throws {
        let file = try tokenFile(Self.tokenA)
        #expect(await VigieAccountsReader(tokenFile: file, fetch: FakeVigie([(Data(#"{"oops":1}"#.utf8), 200)]).fetch).accounts() == nil)
        #expect(await VigieAccountsReader(tokenFile: file, fetch: FakeVigie([(Data(), 500)]).fetch).accounts() == nil)
        struct Down: Error {}
        #expect(await VigieAccountsReader(tokenFile: file, fetch: { _ in throw Down() }).accounts() == nil)
    }

    // MARK: - The words

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Wednesday 18/11/2026, 22:43.
    var now: Date { at(18, 22, 43) }

    func account(week: Double? = nil, resets: Date? = nil, fullAt: Date? = nil, model: (String, Double)? = nil,
                 session: (Double, Date)? = nil) -> ClaudeAccount {
        ClaudeAccount(id: "travail", label: "Travail", isDefault: true, connected: true,
                      usage: .init(session: session.map { .init(pct: $0.0, resetsAt: $0.1) },
                                   week: week.map { .init(pct: $0, resetsAt: resets, fullAt: fullAt) },
                                   weekModel: model.map { .init(label: $0.0, pct: $0.1, resetsAt: resets) }, observedAt: now))
    }

    func row(_ account: ClaudeAccount) -> ClaudeAccountsText.Row {
        ClaudeAccountsText.row(account, now: now, calendar: calendar)
    }

    @Test func rowSaysTheTightestQuota() {
        let fable = row(account(week: 40, resets: at(23, 20), model: ("Fable", 100)))
        #expect(fable.model == "Fable" && fable.verdict == "plein · reprend lun. 20:00" && fable.alarming)
        #expect(fable.percent == "100\u{202F}%" && fable.fraction == 1)
        let filling = row(account(week: 71, resets: at(23, 20), fullAt: at(19, 14)))
        #expect(filling.verdict == "plein demain 14:00" && filling.alarming && filling.model == nil)
        let calm = row(account(week: 12, resets: at(23, 20)))
        #expect(calm.verdict == "tient · lun. 20:00" && !calm.alarming && calm.percent == "12\u{202F}%")
        let unknown = row(account())
        #expect(unknown.verdict == "pas de relevé récent" && unknown.percent == "—" && unknown.fraction == nil && !unknown.alarming)
        #expect(row(account(week: 12, resets: at(23, 20), session: (82, at(18, 23, 40)))).session == "session 82\u{202F}% · reprend à 23:40")
        #expect(row(account(week: 12, resets: at(23, 20), session: (82, at(19, 9)))).session == "session 82\u{202F}% · reprend demain 9:00")
        #expect(row(account(week: 12, resets: at(23, 20), session: (60, at(19, 9)))).session == nil)
    }

    /// Final review: a model's limit higher than the week never hides the week filling before its reset.
    @Test func aModelAheadKeepsTheWeeksForecast() {
        var both = account(week: 71, resets: at(23, 20), fullAt: at(19, 14), model: ("Fable", 80))
        both.usage?.weekModel?.resetsAt = at(23, 20)
        let row = row(both)
        #expect(row.model == "Fable" && row.percent == "80\u{202F}%")
        #expect(row.verdict == "plein demain 14:00" && row.alarming)
    }

    @Test func momentWords() {
        #expect(ClaudeAccountsText.moment(at(18, 23, 40), now: now, calendar: calendar) == "23:40")
        #expect(ClaudeAccountsText.moment(at(19, 9), now: now, calendar: calendar) == "demain 9:00")
        #expect(ClaudeAccountsText.moment(at(23, 20, 15), now: now, calendar: calendar) == "lun. 20:15")
    }
}
