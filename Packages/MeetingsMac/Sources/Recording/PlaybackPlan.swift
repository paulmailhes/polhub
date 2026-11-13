import AVFoundation
import Foundation

/// A piece of a segment file, placed on the meeting's time line (seconds from its origin).
public struct PlaybackPiece: Equatable, Sendable {
    public let url: URL
    public let track: String
    public let atSeconds: Double
    public let fromSeconds: Double
    public let durationSeconds: Double

    public init(url: URL, track: String, atSeconds: Double, fromSeconds: Double, durationSeconds: Double) {
        self.url = url
        self.track = track
        self.atSeconds = atSeconds
        self.fromSeconds = fromSeconds
        self.durationSeconds = durationSeconds
    }
}

/// Lays a meeting's segments on one time line: segment k of a run covers
/// `[start + (k−1)·segmentSeconds, start + k·segmentSeconds[`, the last one being shorter. For `moi`, only
/// what the chosen spans cover is played: one microphone at a time.
public enum PlaybackPlan {
    public static func pieces(
        folder: URL, timeline: MeetingTimeline, moiSpans: [ChosenSpan], originNanos: UInt64, segmentSeconds: Double,
        untilNanos: UInt64? = nil, preferArchive: Bool = true
    ) -> [PlaybackPiece] {
        func seconds(_ nanos: UInt64) -> Double { (Double(nanos) - Double(originNanos)) / 1e9 }
        // Once the meeting is archived (step 2), its two files are the whole meeting.
        if preferArchive, let archive = TrackRenderer.prepared(in: folder) {
            let length = min(archive.seconds, untilNanos.map(seconds) ?? archive.seconds)
            return [("autres", archive.autres), ("moi", archive.moi)].compactMap { track, url in
                url.map { PlaybackPiece(url: $0, track: track, atSeconds: 0, fromSeconds: 0, durationSeconds: length) }
            }
        }
        var pieces: [PlaybackPiece] = []
        for run in timeline.runs {
            let directory = folder.appending(path: "audio/\(run.track)/\(run.folderName)", directoryHint: .isDirectory)
            let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "caf" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let start = seconds(run.startNanos)
            let windows = run.track == "moi"
                ? moiSpans.filter { $0.runID == run.id }.map { (seconds($0.fromNanos), seconds($0.toNanos)) }
                : nil
            for (index, url) in files.enumerated() {
                let segmentStart = start + Double(index) * segmentSeconds
                let length = duration(of: url) ?? segmentSeconds
                guard let windows else {
                    pieces.append(PlaybackPiece(url: url, track: run.track, atSeconds: segmentStart, fromSeconds: 0, durationSeconds: length))
                    continue
                }
                for (from, to) in windows {
                    let begin = max(segmentStart, from), end = min(segmentStart + length, to)
                    guard end - begin > 0.0005 else { continue }
                    pieces.append(PlaybackPiece(
                        url: url, track: run.track, atSeconds: begin, fromSeconds: begin - segmentStart, durationSeconds: end - begin
                    ))
                }
            }
        }
        // The ten minutes of safety after the end are not played back.
        if let untilNanos {
            let end = seconds(untilNanos)
            pieces = pieces.compactMap { piece in
                let length = min(piece.durationSeconds, end - piece.atSeconds)
                guard length > 0.0005 else { return nil }
                return PlaybackPiece(url: piece.url, track: piece.track, atSeconds: piece.atSeconds, fromSeconds: piece.fromSeconds, durationSeconds: length)
            }
        }
        return pieces.sorted { ($0.track, $0.atSeconds) < ($1.track, $1.atSeconds) }
    }

    /// The length of a segment file, read from the file itself.
    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
