import Foundation
import Testing
@testable import HubLink

/// A Mac made up for the tests: it answers what `answers` says, by path.
final class StubMac: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [String: (status: Int, body: Data)] = [:]
    nonisolated(unsafe) static var tokens: [String] = []
    nonisolated(unsafe) static var asleep = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.tokens.append(request.value(forHTTPHeaderField: LinkAPI.authorization) ?? "")
        if Self.asleep {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let answer = Self.answers[request.url?.path ?? ""] ?? (404, Data(#"{"message":"Cette demande n'existe pas."}"#.utf8))
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubMac.self]
        return URLSession(configuration: configuration)
    }
}

/// The iPhone's side (20/11). Serialized: the made-up Mac is shared.
@Suite(.serialized) struct LinkClientTests {
    let connection = LinkConnection(address: URL(string: "https://mac.exemple.ts.net:8443")!, token: "jeton")

    func cache() -> LinkCache {
        LinkCache(folder: FileManager.default.temporaryDirectory.appending(path: "copie-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func aRequestCarriesTheTokenAndReadsTheAnswer() async throws {
        StubMac.asleep = false
        StubMac.tokens = []
        StubMac.answers = [LinkAPI.Path.status: (200, try LinkAPI.encoder.encode(LinkStatus(appVersion: "0.52.0", device: "iPhone")))]
        let client = LinkClient(connection: connection, session: StubMac.session())
        let status = try await client.get(LinkStatus.self, LinkAPI.Path.status)
        #expect(status.appVersion == "0.52.0" && StubMac.tokens == ["Bearer jeton"])
        #expect(client.url(LinkAPI.Path.threads, query: ["dossier": "inbox", "limite": "50"]).absoluteString
                == "https://mac.exemple.ts.net:8443/v1/mail/threads?dossier=inbox&limite=50")
    }

    @Test func aMacThatForgotTheIPhoneSaysSo() async throws {
        StubMac.asleep = false
        StubMac.answers = [LinkAPI.Path.status: (401, try LinkAPI.encoder.encode(LinkError("Cet iPhone n'est plus relié au Mac.")))]
        let client = LinkClient(connection: connection, session: StubMac.session())
        await #expect(throws: LinkFailure.notPaired("Cet iPhone n'est plus relié au Mac.")) {
            _ = try await client.get(LinkStatus.self, LinkAPI.Path.status)
        }
    }

    @Test func aSleepingMacLeavesTheLastCopy() async throws {
        let cache = cache()
        defer { cache.clear() }
        let projects = [LinkProject(id: UUID(), name: "Site vitrine", status: "priorité 2", client: nil, due: nil, task: nil, color: nil)]
        StubMac.asleep = false
        StubMac.answers = [LinkAPI.Path.projects: (200, try LinkAPI.encoder.encode(projects))]
        let client = LinkClient(connection: connection, session: StubMac.session())
        let fresh = try await client.fetch([LinkProject].self, LinkAPI.Path.projects, cache: cache)
        #expect(fresh.value == projects && fresh.keptAt == nil)
        StubMac.asleep = true
        let kept = try await client.fetch([LinkProject].self, LinkAPI.Path.projects, cache: cache)
        #expect(kept.value == projects && kept.keptAt != nil)
        // Nothing kept for this one: the Mac's silence is said.
        await #expect(throws: LinkFailure.unreachable) {
            _ = try await client.fetch([LinkMeeting].self, LinkAPI.Path.meetings, cache: cache)
        }
        StubMac.asleep = false
    }

    @Test func theDatesAreWrittenAsOnTheMac() throws {
        var calendar = LinkWords.calendar
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11, year: Int = 2026) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        let now = date(20, 18)
        #expect(LinkWords.time(date(20, 9, 5), calendar: calendar) == "9:05")
        #expect(LinkWords.listDate(date(20, 9, 5), now: now, calendar: calendar) == "9:05")
        #expect(LinkWords.listDate(date(19, 9), now: now, calendar: calendar) == "hier")
        #expect(LinkWords.listDate(date(17, 9), now: now, calendar: calendar) == "mar.")
        #expect(LinkWords.listDate(date(1, 9, month: 12, year: 2025), now: now, calendar: calendar) == "1er déc. 2025")
        #expect(LinkWords.dayTitle(date(21, 9), now: now, calendar: calendar) == "Demain")
        #expect(LinkWords.dayTitle(date(26, 9), now: now, calendar: calendar) == "Jeudi 26 novembre")
        #expect(LinkWords.duration(65 * 60) == "1 h 05" && LinkWords.duration(42 * 60) == "42 min" && LinkWords.duration(7_200) == "2 h")
        #expect(LinkWords.kept(date(20, 9, 5), now: now, calendar: calendar) == "copie de 9:05")
        #expect(LinkWords.kept(date(19, 18, 42), now: now, calendar: calendar) == "copie d'hier 18:42")
    }
}
