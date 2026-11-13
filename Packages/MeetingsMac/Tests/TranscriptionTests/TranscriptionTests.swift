import Domain
import Foundation
import Testing
@testable import Transcription

@Suite struct ChunkPlanTests {
    @Test func regionsCloserThanFourSecondsMerge() {
        let chunks = ChunkPlan.chunks([SpeechRegion(start: 10, end: 12), SpeechRegion(start: 15, end: 17), SpeechRegion(start: 30, end: 31)], duration: 100)
        #expect(chunks == [Chunk(index: 0, start: 9.5, end: 17.5), Chunk(index: 1, start: 29.5, end: 31.5)])
    }

    @Test func aChunkNeverExceeds29Seconds() {
        let regions = stride(from: 0.0, to: 120, by: 3).map { SpeechRegion(start: $0, end: $0 + 2) }
        let long = [SpeechRegion(start: 200, end: 270)]
        let chunks = ChunkPlan.chunks(regions + long, duration: 300)
        #expect(chunks.allSatisfy { $0.end - $0.start <= 29 + 1e-9 })
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
        // The long region is cut in equal parts that cover it entirely.
        let parts = chunks.filter { $0.start >= 199 }
        #expect(parts.count == 3 && parts.first?.start == 199.5 && parts.last?.end == 270.5)
    }

    @Test func paddingStaysInsideTheTrack() {
        let chunks = ChunkPlan.chunks([SpeechRegion(start: 0.2, end: 3), SpeechRegion(start: 58, end: 59.9)], duration: 60)
        #expect(chunks.first?.start == 0 && chunks.last?.end == 60)
    }

    @Test func noRegionNoChunk() {
        #expect(ChunkPlan.chunks([], duration: 3_600).isEmpty)
    }
}

@Suite struct TranscriptChecksTests {
    func result(_ texts: [(String, Double)], chunk: Chunk = Chunk(index: 0, start: 0, end: 20), track: Speaker = .autres) -> ChunkResult {
        var start = chunk.start
        let segments = texts.map { text, ratio in
            defer { start += 2 }
            return EngineSegment(start: start, end: start + 2, text: text, avgLogprob: -0.3, compressionRatio: ratio, noSpeechProb: 0.1)
        }
        return ChunkResult(track: track, chunk: chunk, segments: segments)
    }

    @Test func aLoopSegmentIsRemoved() {
        let clean = TranscriptChecks.clean([result([("on y va on y va on y va on y va on y va", 2.6), ("Bonjour à tous.", 1.1)])])
        #expect(clean[0].segments.map(\.text) == ["Bonjour à tous."])
        #expect(clean[0].removed.map(\.reason) == [.loop])
    }

    @Test func knownPhantomsAreRemoved() {
        let clean = TranscriptChecks.clean([result([
            ("Sous-titrage Société Radio-Canada", 1.2), ("Sous-titrage ST' 501", 1.1),
            ("Sous-titres réalisés par la communauté d'Amara.org", 1.3), ("Merci d'avoir regardé cette vidéo !", 1.2),
            ("On regarde le budget.", 1.1),
        ])])
        #expect(clean[0].segments.map(\.text) == ["On regarde le budget."])
        #expect(clean[0].removed.count == 4 && clean[0].removed.allSatisfy { $0.reason == .phantom })
    }

    @Test func aLoneThanksInAShortChunkIsRemoved() {
        let clean = TranscriptChecks.clean([result([("Merci.", 1)], chunk: Chunk(index: 0, start: 40, end: 41.5))])
        #expect(clean[0].segments.isEmpty)
    }

    @Test func aThanksInsideASentenceStays() {
        let long = TranscriptChecks.clean([result([("Merci.", 1)], chunk: Chunk(index: 0, start: 40, end: 45))])
        let sentence = TranscriptChecks.clean([result([("Merci pour le retour sur la maquette.", 1)], chunk: Chunk(index: 0, start: 40, end: 41.5))])
        #expect(long[0].segments.count == 1 && sentence[0].segments.count == 1)
    }

    @Test func tooManyWordsPerSecondIsDoubtful() {
        let fast = String(repeating: "mot ", count: 70)   // 70 mots en 10 s
        let clean = TranscriptChecks.clean([result([(fast, 1.5)], chunk: Chunk(index: 0, start: 0, end: 10))])
        #expect(clean[0].doubtful && clean[0].segments.count == 1)
        let normal = TranscriptChecks.clean([result([("On se voit jeudi pour la suite.", 1.1)], chunk: Chunk(index: 0, start: 0, end: 10))])
        #expect(!normal[0].doubtful)
    }

    /// A real meeting of 16/09: the same sentence over 51 minutes. It must never be kept as is.
    @Test func theSyntheticLoopFixtureIsFlagged() {
        let results = (0..<400).map { index -> ChunkResult in
            let chunk = Chunk(index: index, start: Double(index) * 7.6, end: Double(index) * 7.6 + 7)
            return ChunkResult(track: .moi, chunk: chunk, segments: [EngineSegment(
                start: chunk.start, end: chunk.end, text: "Je vous remercie de votre attention.", avgLogprob: -0.2,
                compressionRatio: 1.2, noSpeechProb: 0.3
            )])
        }
        let clean = TranscriptChecks.clean(results)
        let kept = clean.flatMap(\.segments).count
        #expect(kept <= 1)
        #expect(clean.contains { $0.doubtful })
    }

    // Revue finale, Important 1 : des réponses courtes fréquentes ne sont pas une boucle.
    @Test func aShortReplySaidOftenStaysUnflagged() {
        let results = (0..<6).map { index in
            result([("Oui, c'est ça.", 1), ("On avance sur le point \(index).", 1)],
                   chunk: Chunk(index: index, start: Double(index) * 30, end: Double(index) * 30 + 10))
        }
        let clean = TranscriptChecks.clean(results)
        #expect(clean.flatMap(\.segments).count == 12)
        #expect(!clean.contains { $0.doubtful })
    }

    @Test func aLongSentenceComingBackTenTimesIsALoop() {
        let results = (0..<12).map { index in
            result([("Je vous remercie de votre attention.", 1), ("Point \(index) de l'ordre du jour.", 1)],
                   chunk: Chunk(index: index, start: Double(index) * 30, end: Double(index) * 30 + 10))
        }
        let clean = TranscriptChecks.clean(results)
        #expect(clean.flatMap(\.segments).filter { $0.text.hasPrefix("Je vous") }.count == 1)
        #expect(clean.flatMap(\.segments).count == 13)
    }

    @Test func threeIdenticalSentencesInARowAreALoop() {
        let clean = TranscriptChecks.clean([result([
            ("On se retrouve la semaine prochaine alors.", 1), ("On se retrouve la semaine prochaine alors.", 1),
            ("On se retrouve la semaine prochaine alors.", 1),
        ], chunk: Chunk(index: 0, start: 0, end: 20))])
        #expect(clean[0].segments.count == 1 && clean[0].doubtful)
    }

    // Revue finale, mineur 1 regradé : un mot fantôme dans une vraie phrase ne la fait pas disparaître.
    @Test func aPhantomWordInsideARealSentenceStays() {
        let clean = TranscriptChecks.clean([result([
            ("Il faut ajouter le bouton abonnez-vous en bas de la page.", 1),
            ("Merci d'avoir regardé les maquettes hier soir.", 1),
            ("Le sous-titrage des vidéos, on le fait pour le client ?", 1),
            ("Sous-titrage FR 2021", 1),
        ])])
        #expect(clean[0].segments.count == 3)
        #expect(clean[0].removed.map(\.text) == ["Sous-titrage FR 2021"])
    }

    @Test func shortRepeatedAnswersStay() {
        let results = (0..<10).map { index in
            result([("Oui.", 1)], chunk: Chunk(index: index, start: Double(index) * 10, end: Double(index) * 10 + 3))
        }
        #expect(TranscriptChecks.clean(results).flatMap(\.segments).count == 10)
    }
}

@Suite struct DialogueTests {
    func clean(_ track: Speaker, _ segments: [(Double, Double, String)], doubtful: Bool = false) -> CleanChunk {
        CleanChunk(
            track: track, chunk: Chunk(index: 0, start: segments.first?.0 ?? 0, end: segments.last?.1 ?? 0),
            segments: segments.map { EngineSegment(start: $0.0, end: $0.1, text: $0.2, avgLogprob: -0.2, compressionRatio: 1, noSpeechProb: 0.1) },
            doubtful: doubtful, removed: []
        )
    }

    @Test func twoTracksInterleaveByTime() {
        let lines = Dialogue.lines([
            clean(.moi, [(0, 2, "Salut."), (10, 12, "Ça marche.")]),
            clean(.autres, [(4, 8, "Bonjour, on commence ?")]),
        ])
        #expect(lines.map(\.speaker) == [.moi, .autres, .moi])
        #expect(lines.map(\.text) == ["Salut.", "Bonjour, on commence ?", "Ça marche."])
    }

    @Test func closeSegmentsOfTheSameSpeakerMerge() {
        let lines = Dialogue.lines([clean(.autres, [(0, 3, " Alors,"), (3.5, 6, "on regarde le planning."), (9, 10, "Voilà.")], doubtful: true)])
        #expect(lines.count == 2)
        #expect(lines[0] == DialogueLine(speaker: .autres, start: 0, end: 6, text: "Alors, on regarde le planning.", doubtful: true))
    }

    @Test func aMergedLineNeverExceedsSixtySeconds() {
        let segments = stride(from: 0.0, to: 120, by: 5).map { ($0, $0 + 4.5, "phrase") }
        let lines = Dialogue.lines([clean(.autres, segments)])
        #expect(lines.count >= 2 && lines.allSatisfy { $0.end - $0.start <= 60 })
    }

    @Test func emptySegmentsDisappear() {
        #expect(Dialogue.lines([clean(.moi, [(0, 1, "  "), (5, 6, "Oui.")])]).map(\.text) == ["Oui."])
    }
}

// Revue finale, mineur 3 regradé : un arrêt brutal au milieu d'une ligne ne fait pas perdre le morceau suivant.
@Suite struct ChunkResultFileTests {
    func result(_ index: Int) -> ChunkResult {
        ChunkResult(track: .moi, chunk: Chunk(index: index, start: Double(index), end: Double(index) + 1), segments: [])
    }

    @Test func aTornLastLineDoesNotSwallowTheNextChunk() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "coupée \(UUID().uuidString)/moi.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try ChunkResultFile.append(result(0), to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"track":"moi","chunk":{"ind"#.utf8))
        try handle.close()
        try ChunkResultFile.append(result(1), to: url)
        #expect(ChunkResultFile.read(url).map(\.chunk.index) == [0, 1])
    }

    @Test func aChunkWrittenTwiceIsReadOnce() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "double \(UUID().uuidString)/moi.jsonl")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for index in [0, 1, 1] { try ChunkResultFile.append(result(index), to: url) }
        #expect(ChunkResultFile.read(url).map(\.chunk.index) == [0, 1])
    }
}

@Suite struct CalculProtocolTests {
    @Test func everyMessageRoundTrips() throws {
        let messages: [CalculMessage] = [
            .progress(track: .moi, done: 3, total: 12),
            .chunk(ChunkResult(track: .autres, chunk: Chunk(index: 2, start: 10, end: 20), segments: [
                EngineSegment(start: 10.5, end: 12, text: "Bonjour.", avgLogprob: -0.25, compressionRatio: 1.1, noSpeechProb: 0.05),
            ])),
            .finished,
            .failed("Le modèle manque : whisperkit"),
        ]
        for message in messages {
            let line = try JSONEncoder().encode(message)
            #expect(!line.contains(UInt8(ascii: "\n")))
            #expect(try JSONDecoder().decode(CalculMessage.self, from: line) == message)
        }
        let request = CalculRequest(folder: "/tmp/r", language: nil)
        #expect(try JSONDecoder().decode(CalculRequest.self, from: try JSONEncoder().encode(request)) == request)
    }
}
