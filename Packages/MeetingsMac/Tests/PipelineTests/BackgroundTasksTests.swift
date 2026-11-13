import Domain
import Foundation
import Persistence
import Testing
@testable import Pipeline

@Suite struct BackgroundTasksTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-13T10:00:00Z")!
    let day = 86_400.0

    func row(transcribedDaysAgo: Double?, purged: Bool = false, deleted: Bool = false, endedDaysAgo: Double = 90) -> MeetingRow {
        let start = now.addingTimeInterval(-endedDaysAgo * day)
        return MeetingRow(
            createdAt: start, status: .ended, source: .dia, candidateKey: "k", title: "R", startedAt: start,
            deletedAt: deleted ? now : nil, endedAt: start.addingTimeInterval(3_600),
            transcribedAt: transcribedDaysAgo.map { now.addingTimeInterval(-$0 * day) },
            audioPurgedAt: purged ? now : nil
        )
    }

    // Choix validé : l'audio enregistré avant la transcription (étape 1) garde ses 30 jours à partir d'elle.
    @Test func aMeetingNeverTranscribedIsKept() {
        #expect(AudioPurge.due([row(transcribedDaysAgo: nil)], now: now).isEmpty)
    }

    @Test func audioIsPurgedThirtyDaysAfterTranscription() {
        let old = row(transcribedDaysAgo: 31)
        let recent = row(transcribedDaysAgo: 29)
        let purged = row(transcribedDaysAgo: 40, purged: true)
        let deleted = row(transcribedDaysAgo: 40, deleted: true)
        #expect(AudioPurge.due([old, recent, purged, deleted], now: now).map(\.id) == [old.id])
    }

    // Étape 2 : l'archive 16 kHz part avec le brut, la transcription reste.
    @Test func thePurgeRemovesTheRawAudioAndTheArchive() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "purge \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, logs: root.appending(path: "logs"))
        let store = MeetingStore(try AppDatabase.inMemory())
        let old = row(transcribedDaysAgo: 31)
        try store.save(old)
        let folder = paths.meetingFolder(old.id)
        for name in ["audio/autres/b01", "pistes"] {
            try FileManager.default.createDirectory(at: folder.appending(path: name), withIntermediateDirectories: true)
        }
        try Data("{}".utf8).write(to: folder.appending(path: "meeting.json"))
        #expect(try AudioPurge.run(store: store, paths: paths, now: now) == 1)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(left == ["meeting.json"])
    }

    // Revue finale, Important 6 : l'audio d'une transcription en échec part aussi à 30 jours (choix validé),
    // avec une alerte à partir du 23ᵉ jour.
    @Test func audioOfAFailedTranscriptionGoesAfterThirtyDays() {
        let old = row(transcribedDaysAgo: nil, endedDaysAgo: 31)
        let recent = row(transcribedDaysAgo: nil, endedDaysAgo: 20)
        let notFailed = row(transcribedDaysAgo: nil, endedDaysAgo: 40)
        let failed: Set<UUID> = [old.id, recent.id]
        #expect(AudioPurge.due([old, recent, notFailed], failed: failed, now: now).map(\.id) == [old.id])
    }

    @Test func aFailedTranscriptionWarnsFromTheTwentyThirdDay() {
        let soon = row(transcribedDaysAgo: nil, endedDaysAgo: 23.5)
        let early = row(transcribedDaysAgo: nil, endedDaysAgo: 22)
        let warnings = AudioPurge.warnings([soon, early], failed: [soon.id, early.id], now: now)
        #expect(warnings.map(\.meetingID) == [soon.id])
        #expect(warnings.first?.message == "L'audio de « R » sera effacé dans 7 jours : sa transcription a échoué. « Réessayer » dans la fenêtre.")
        #expect(warnings.first?.kind == .alert)
    }

    @Test func keepsSevenDailyBackups() {
        let names = (1...9).map { String(format: "Transcriptor-202611%02d.sqlite", $0) } + ["notes.txt"]
        #expect(DatabaseBackup.toRemove(names) == ["Transcriptor-20261102.sqlite", "Transcriptor-20261101.sqlite"])
        #expect(DatabaseBackup.toRemove(["Transcriptor-20261101.sqlite"]).isEmpty)
    }

    @Test func aMemorySampleIsComplete() {
        let sample = MemorySampler.sample(pressure: .warning, at: now)
        #expect(sample.pressure == "warning" && sample.at == now)
        #expect(sample.freeBytes > 0 && sample.wiredBytes > 0 && sample.activeBytes > 0)
    }

    @Test func oldDetectionLogsGoAfterThirtyDays() {
        let names = ["detection-20261001.jsonl", "detection-20261020.jsonl", "detection-20261113.jsonl", "autre.jsonl"]
        #expect(AudioPurge.expiredLogs(names, now: now) == ["detection-20261001.jsonl"])
    }
}
