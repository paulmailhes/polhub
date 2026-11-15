import AVFoundation
import Combine
import Foundation
import Recording

/// Plays a meeting: « Moi » and « Les autres » on two tracks of one composition, in phase, each of which
/// can be silenced.
@MainActor
public final class MeetingPlayer: ObservableObject {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentSeconds: Double = 0
    @Published public var moiEnabled = true { didSet { applyMix() } }
    @Published public var autresEnabled = true { didSet { applyMix() } }
    /// The speed, from the player's menu (15/11); it applies at once while playing.
    @Published public var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }
    public let durationSeconds: Double

    /// The speeds of the menu.
    public static let rates: [Float] = [1, 1.25, 1.5, 2]
    /// How long « −15 s » and « +15 s » jump.
    public static let skipSeconds: Double = 15

    /// « 1× », « 1,25× ».
    public static func rateLabel(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_FR"))) + "×"
    }

    let composition: AVMutableComposition
    private let tracks: [String: AVMutableCompositionTrack]
    /// The source files stay open while the meeting is played.
    private let sources: [AVURLAsset]
    private let item: AVPlayerItem
    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    public init(pieces: [PlaybackPiece]) async throws {
        let composition = AVMutableComposition()
        var tracks: [String: AVMutableCompositionTrack] = [:]
        for name in ["moi", "autres"] {
            tracks[name] = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        let scale: CMTimeScale = 48_000
        var sources: [AVURLAsset] = []
        // Pieces go in time order; a track cannot receive audio beyond its end, so the silence between two
        // pieces is inserted first.
        for piece in pieces.sorted(by: { $0.atSeconds < $1.atSeconds }) {
            // The asset must outlive the insertion: a track whose asset is gone cannot be read (error -12780).
            let asset = AVURLAsset(url: piece.url)
            guard let target = tracks[piece.track],
                  let source = try await asset.loadTracks(withMediaType: .audio).first
            else { continue }
            let end = target.timeRange.end.isValid ? target.timeRange.end : .zero
            var at = CMTime(seconds: piece.atSeconds, preferredTimescale: scale)
            if at > end {
                target.insertEmptyTimeRange(CMTimeRange(start: end, end: at))
            } else {
                at = end   // never push back audio already placed
            }
            let range = CMTimeRange(
                start: CMTime(seconds: piece.fromSeconds, preferredTimescale: scale),
                duration: CMTime(seconds: piece.durationSeconds, preferredTimescale: scale)
            )
            try target.insertTimeRange(range, of: source, at: at)
            sources.append(asset)
        }
        self.composition = composition
        self.tracks = tracks
        self.sources = sources
        durationSeconds = pieces.map { $0.atSeconds + $0.durationSeconds }.max() ?? 0
        item = AVPlayerItem(asset: composition)
        player = AVPlayer(playerItem: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.currentSeconds = time.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
        applyMix()
    }

    public func play() {
        if currentSeconds >= durationSeconds - 0.1 { seek(to: 0) }
        player.defaultRate = rate
        player.play()
        isPlaying = true
    }

    /// « −15 s », « +15 s »: never before the start nor past the end.
    public func skip(by seconds: Double) {
        seek(to: min(max(0, currentSeconds + seconds), durationSeconds))
    }

    /// The speed the player plays at (tests).
    var playbackRate: Float { player.defaultRate }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        currentSeconds = seconds
    }

    /// The start of every piece of audio on each track, in seconds.
    func segmentStarts() -> [String: [Double]] {
        tracks.mapValues { track in track.segments.filter { !$0.isEmpty }.map { $0.timeMapping.target.start.seconds } }
    }

    private func applyMix() {
        let mix = AVMutableAudioMix()
        mix.inputParameters = tracks.map { name, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume((name == "moi" ? moiEnabled : autresEnabled) ? 1 : 0, at: .zero)
            return parameters
        }
        item.audioMix = mix
    }
}
