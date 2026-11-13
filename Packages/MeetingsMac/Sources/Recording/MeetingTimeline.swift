import AudioCapture
import Foundation

/// One second of a stream, as the timeline reports it.
public struct SecondSample: Equatable, Sendable, Codable {
    public let nanos: UInt64
    public let rms: Float
    public let peak: Float

    public init(nanos: UInt64, rms: Float, peak: Float) {
        self.nanos = nanos
        self.rms = rms
        self.peak = peak
    }
}

/// One build of one stream: the tap, or one microphone. Its segments are `audio/<track>/<folderName>/`.
public struct StreamRun: Equatable, Sendable, Identifiable {
    public var id: String { "\(track)/\(build)" }
    public let track: String
    public let device: String?
    public let build: Int
    public let sampleRate: Double
    /// When its frame 0 was heard, in continuous nanoseconds: `anchor.continuousNanos − frameIndex / sampleRate`.
    public let startNanos: UInt64
    public let seconds: [SecondSample]

    public init(track: String, device: String?, build: Int, sampleRate: Double, startNanos: UInt64, seconds: [SecondSample]) {
        self.track = track
        self.device = device
        self.build = build
        self.sampleRate = sampleRate
        self.startNanos = startNanos
        self.seconds = seconds
    }

    public var folderName: String { CaptureEngine.folderName(build: build, device: device) }
    public var endNanos: UInt64 { seconds.last?.nanos ?? startNanos }
}

/// What a meeting's recording went through.
public struct MeetingHealth: Equatable, Sendable, Codable {
    public let moiSeconds: Int
    public let autresSeconds: Int
    public let gapCount: Int
    public let rebuilds: Int
    public let selfTestPassed: Bool?
    public let errors: [String]

    public init(moiSeconds: Int, autresSeconds: Int, gapCount: Int, rebuilds: Int, selfTestPassed: Bool?, errors: [String]) {
        self.moiSeconds = moiSeconds
        self.autresSeconds = autresSeconds
        self.gapCount = gapCount
        self.rebuilds = rebuilds
        self.selfTestPassed = selfTestPassed
        self.errors = errors
    }

    public static let empty = MeetingHealth(moiSeconds: 0, autresSeconds: 0, gapCount: 0, rebuilds: 0, selfTestPassed: nil, errors: [])
}

/// A meeting's `timeline.jsonl`, read back after the meeting.
public struct MeetingTimeline: Sendable {
    public let runs: [StreamRun]
    public let rebuilds: Int
    public let selfTestPassed: Bool?
    public let errors: [String]
    let secondsByTrack: [String: Int]
    let gapCount: Int

    public static let empty = MeetingTimeline(runs: [], rebuilds: 0, selfTestPassed: nil, errors: [], secondsByTrack: [:], gapCount: 0)

    public var health: MeetingHealth {
        MeetingHealth(
            moiSeconds: secondsByTrack["moi"] ?? 0, autresSeconds: secondsByTrack["autres"] ?? 0,
            gapCount: gapCount, rebuilds: rebuilds, selfTestPassed: selfTestPassed, errors: errors
        )
    }

    private struct Line: Decodable {
        struct Payload: Decodable {
            let track: String?
            let device: String?
            let build: Int?
            let stats: LevelStats?
            let anchor: TimeAnchor?
            let format: PCMFormat?
            let streamFormat: PCMFormat?
            let gaps: [Gap]?
            let passed: Bool?
            let message: String?
        }

        let kind: String
        let data: Payload
    }

    /// A line that cannot be read (the last one, cut by a crash) is skipped.
    public static func read(_ url: URL) throws -> MeetingTimeline {
        let decoder = JSONDecoder()
        var rates: [String: Double] = [:]
        var order: [String] = []
        var devices: [String: String?] = [:]
        var anchors: [String: TimeAnchor] = [:]
        var samples: [String: [SecondSample]] = [:]
        var secondsByTrack: [String: Int] = [:]
        var rebuilds = 0, gapCount = 0
        var selfTest: Bool?
        var errors: [String] = []

        for raw in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard let line = try? decoder.decode(Line.self, from: Data(raw.utf8)) else { continue }
            let data = line.data
            switch line.kind {
            case "mic-start":
                if let build = data.build, let format = data.format { rates["moi/\(build)"] = format.sampleRate }
            case "capture-start":
                if let build = data.build, let format = data.streamFormat { rates["autres/\(build)"] = format.sampleRate }
            case "capture":
                // A second during which nothing came is reported with no frame: it is no audio.
                guard let track = data.track, let build = data.build, let stats = data.stats, let anchor = data.anchor,
                      stats.frames > 0 else { continue }
                let id = "\(track)/\(build)"
                if samples[id] == nil {
                    order.append(id)
                    devices[id] = data.device
                    anchors[id] = anchor
                }
                samples[id, default: []].append(SecondSample(nanos: anchor.continuousNanos, rms: stats.rms, peak: stats.peak))
                secondsByTrack[track, default: 0] += 1
            case "rebuild":
                rebuilds += 1
            case "gaps":
                gapCount += data.gaps?.count ?? 0
            case "self-test":
                selfTest = data.passed
            case "capture-error":
                if let message = data.message { errors.append(message) }
            default:
                break
            }
        }

        let runs = order.compactMap { id -> StreamRun? in
            guard let anchor = anchors[id], let slash = id.firstIndex(of: "/"), let build = Int(id[id.index(after: slash)...])
            else { return nil }
            let track = String(id[..<slash])
            let rate = rates[id] ?? 48_000
            let offset = UInt64((Double(anchor.frameIndex) / rate * 1e9).rounded())
            return StreamRun(
                track: track, device: devices[id] ?? nil, build: build, sampleRate: rate,
                startNanos: anchor.continuousNanos > offset ? anchor.continuousNanos - offset : 0,
                seconds: samples[id] ?? []
            )
        }
        return MeetingTimeline(
            runs: runs, rebuilds: rebuilds, selfTestPassed: selfTest, errors: errors,
            secondsByTrack: secondsByTrack, gapCount: gapCount
        )
    }
}
