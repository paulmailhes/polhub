import Domain
import Foundation
import Testing
@testable import MeetingDetection

/// The detector replayed on the guided call of 13 November 2026 (phase 0): tab readings and Dia's audio
/// state, second by second, as they were measured.
@Suite struct ReplayTests {
    struct Line: Decodable {
        struct Payload: Decodable {
            let holdsMic: Bool?
            let playing: Bool?
            let result: String?
            let tabs: [BrowserTab]?
            let id: String?
        }

        let up: Double
        let kind: String
        let data: Payload
    }

    static let code = "abc-defg-hij"

    func lines() throws -> [Line] {
        let url = try #require(Bundle.module.url(forResource: "appel-2026-11-13", withExtension: "jsonl", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(Line.self, from: Data($0.utf8)) }
    }

    func input(_ line: Line) -> DetectionInput? {
        switch line.kind {
        case "audio-procs":
            .audio(DiaAudio(holdsMic: line.data.holdsMic ?? false, playing: line.data.playing ?? false))
        case "tabs":
            switch line.data.result {
            case "tabs": .tabs(line.data.tabs ?? [], complete: true)
            case "partial": .tabs(line.data.tabs ?? [], complete: false)
            default: .tabsUnavailable(line.data.result ?? "?")
            }
        default:
            nil
        }
    }

    func hasTheTab(_ line: Line) -> Bool {
        line.kind == "tabs" && (line.data.tabs ?? []).contains { $0.url.contains(Self.code) }
    }

    /// The `up` of the first line after the first marker `marker` that matches.
    struct Missing: Error { let marker: String }

    func firstUp(_ lines: [Line], after marker: String, where match: (Line) -> Bool) throws -> Double {
        guard let start = lines.firstIndex(where: { $0.kind == "marker" && $0.data.id == marker }),
              let found = lines[start...].first(where: match)
        else { throw Missing(marker: marker) }
        return found.up
    }

    @Test func replaysTheGuidedCallOfThirteenNovember() throws {
        let lines = try lines()
        var detector = MeetingDetector()
        var effects: [TimedEffect] = []
        for line in lines {
            if let input = input(line) { effects += detector.handle(input, at: line.up) }
        }
        effects += detector.advance(to: (lines.last?.up ?? 0) + 1)

        let names = effects.map { effect -> String in
            switch effect.effect {
            case .prompt: "prompt"
            case .confirm: "confirm"
            case .presumedEnd: "presumedEnd"
            case .resume: "resume"
            case .end(_, _, let reason): "end:\(reason.rawValue)"
            default: "\(effect.effect)"
            }
        }
        #expect(names == ["prompt", "confirm", "presumedEnd", "resume", "end:tabClosed", "prompt", "confirm", "end:tabClosed"])
        guard effects.count == 8 else { return }

        // S02: the tab of the meeting appears (≈ 09:47:07); ten seconds later, the recording is confirmed.
        let seen = lines.first(where: hasTheTab)
        let firstSeen = try #require(seen).up
        #expect(effects[0].at == firstSeen)
        #expect(effects[1].at == firstSeen + 10)

        // S13: Paul hangs up; Dia lets go of the microphone (≈ 09:53:36); five seconds later, presumed end.
        let released = try firstUp(lines, after: "S13") { $0.kind == "audio-procs" && $0.data.holdsMic == false }
        #expect(effects[2] == TimedEffect(at: released + 5, effect: effects[2].effect))
        if case .presumedEnd(_, let endedAt) = effects[2].effect { #expect(endedAt == released) }

        // S15: Paul rejoins in the same tab (≈ 09:54:02), then hangs up and closes it (≈ 09:54:11).
        let retaken = try firstUp(lines, after: "S15") { $0.kind == "audio-procs" && $0.data.holdsMic == true }
        #expect(effects[3].at >= retaken && effects[3].at <= retaken + 2)
        let gone = try firstUp(lines, after: "S15") { $0.kind == "tabs" && $0.data.result == "tabs" && $0.up > retaken && !hasTheTab($0) }
        #expect(effects[4].at >= gone && effects[4].at <= gone + 2)

        // S16: the link opened again is a new meeting (≈ 09:54:19), closed with its tab (≈ 09:54:44).
        let reopened = try firstUp(lines, after: "S16", where: hasTheTab)
        #expect(effects[5].at == reopened)
        #expect(effects[6].at == reopened + 10)
        let closed = try firstUp(lines, after: "S16") { $0.kind == "tabs" && $0.data.result == "tabs" && $0.up > reopened && !hasTheTab($0) }
        #expect(effects[7].at >= closed && effects[7].at <= closed + 2)

        // S07 to S09: a VoiceInk dictation and a reload of the tab change nothing.
        let quietFrom = try firstUp(lines, after: "S07") { _ in true }
        let quietTo = try firstUp(lines, after: "S10") { _ in true }
        #expect(!effects.contains { $0.at >= quietFrom && $0.at < quietTo })
    }
}
