import Domain
import Foundation
import Persistence
import Testing
@testable import ReadingKit

struct Fixture {
    let now = ISO8601DateFormatter().date(from: "2026-11-13T12:30:00Z")!
    let meetings: MeetingStore
    let transcripts: TranscriptStore
    let hebdo: MeetingRow
    let client: MeetingRow

    init() throws {
        let database = try AppDatabase.inMemory()
        meetings = MeetingStore(database)
        transcripts = TranscriptStore(database)
        let start = ISO8601DateFormatter().date(from: "2026-11-13T12:08:26Z")!
        hebdo = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "t/a", title: "Point hebdo Studio",
                           startedAt: start, endedAt: start.addingTimeInterval(1_500), transcribedAt: start.addingTimeInterval(1_800))
        let earlier = start.addingTimeInterval(-86_400)
        client = MeetingRow(createdAt: earlier, status: .ended, source: .dia, candidateKey: "t/b", title: "Atelier client",
                            startedAt: earlier, endedAt: earlier.addingTimeInterval(600))
        try meetings.save(hebdo)
        try meetings.save(client)
        try transcripts.replaceUtterances(meetingID: hebdo.id, [
            UtteranceRow(meetingID: hebdo.id, speaker: .autres, startMs: 4_000, endMs: 6_000, text: "On regarde le budget.", doubtful: false),
            UtteranceRow(meetingID: hebdo.id, speaker: .moi, startMs: 724_000, endMs: 726_000, text: "Je m'en occupe.", doubtful: true),
        ])
        var job = JobRow(meetingID: hebdo.id, state: .done, language: "fr", doubtful: true, createdAt: start)
        job.progress = 1
        try transcripts.save(job)
    }

    var reader: MeetingReader { MeetingReader(meetings: meetings, transcripts: transcripts, now: { [now] in now }, timeZone: TimeZone(identifier: "Europe/Paris")!) }
}

@Suite struct MeetingTextsTests {
    @Test func theListShowsDateDurationAndState() throws {
        let text = try Fixture().reader.list(since: nil, limit: 20)
        #expect(text.contains("1. 13/11/2026 13:08 · Point hebdo Studio · 25 min · transcrite, à vérifier"))
        #expect(text.contains("2. 12/11/2026 13:08 · Atelier client · 10 min · pas encore transcrite"))
    }

    @Test func aMeetingShowsItsDialogue() throws {
        let fixture = try Fixture()
        let text = try fixture.reader.meeting("1", page: 1)
        #expect(text.contains("# Point hebdo Studio"))
        #expect(text.contains("[0:04] Les autres : On regarde le budget."))
        #expect(text.contains("[12:04] Moi : Je m'en occupe. (à vérifier)"))
        #expect(try fixture.reader.meeting("atelier", page: 1).contains("# Atelier client"))
        #expect(try fixture.reader.meeting(String(fixture.hebdo.id.uuidString.prefix(8)).lowercased(), page: 1).contains("# Point hebdo Studio"))
    }

    @Test func aLongTranscriptIsPaged() throws {
        let fixture = try Fixture()
        try fixture.transcripts.replaceUtterances(meetingID: fixture.hebdo.id, (0..<450).map {
            UtteranceRow(meetingID: fixture.hebdo.id, speaker: .autres, startMs: $0 * 1_000, endMs: $0 * 1_000 + 900, text: "Ligne \($0).", doubtful: false)
        })
        let second = try fixture.reader.meeting("1", page: 2)
        #expect(second.contains("page 2 sur 3"))
        #expect(second.contains("Ligne 200.") && !second.contains("Ligne 199.") && !second.contains("Ligne 400."))
    }

    @Test func anUntranscribedMeetingSaysSo() throws {
        #expect(try Fixture().reader.meeting("2", page: 1).contains("Pas encore transcrite."))
    }

    @Test func theSearchGivesMeetingAndMoment() throws {
        let text = try Fixture().reader.search("budget", limit: 20)
        #expect(text.contains("Point hebdo Studio") && text.contains("[0:04] Les autres") && text.contains("«budget»"))
    }
}

@Suite struct MCPServerTests {
    func call(_ server: MCPServer, _ json: String) throws -> [String: Any] {
        let answer = try #require(server.handle(json))
        return try #require(JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any])
    }

    func toolText(_ answer: [String: Any]) -> (String, Bool) {
        let result = answer["result"] as? [String: Any]
        let content = (result?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        return (content, result?["isError"] as? Bool ?? false)
    }

    @Test func initializeAnswersWithTheRequestedVersion() throws {
        let answer = try call(MCPServer(reader: try Fixture().reader), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let result = try #require(answer["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "transcriptor")
        #expect(answer["id"] as? Int == 1)
    }

    @Test func toolsListNamesTheThreeTools() throws {
        let answer = try call(MCPServer(reader: try Fixture().reader), #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try #require((answer["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["reunions", "reunion", "chercher"])
    }

    @Test func callingReunionReturnsTheDialogue() throws {
        let answer = try call(MCPServer(reader: try Fixture().reader),
                              #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"reunion","arguments":{"quelle":"1"}}}"#)
        let (text, isError) = toolText(answer)
        #expect(!isError && text.contains("On regarde le budget."))
    }

    @Test func anUnknownMethodIs32601() throws {
        let answer = try call(MCPServer(reader: try Fixture().reader), #"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#)
        #expect((answer["error"] as? [String: Any])?["code"] as? Int == -32601)
    }

    @Test func aMissingArgumentIsAToolError() throws {
        let answer = try call(MCPServer(reader: try Fixture().reader),
                              #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"chercher","arguments":{}}}"#)
        let (text, isError) = toolText(answer)
        #expect(isError && text.contains("texte"))
    }

    @Test func notificationsGetNoAnswer() throws {
        #expect(MCPServer(reader: try Fixture().reader).handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }
}
