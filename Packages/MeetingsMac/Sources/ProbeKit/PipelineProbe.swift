import Domain
import Foundation
import MeetingDetection
import MeetingsUI
import Observability
import Persistence
import Pipeline
import Recording

/// `--probe pipeline`: the whole chain of step 1 on this Mac, in a base of its own inside the probe's
/// folder: « Enregistrer maintenant », stop after `--seconds`, finalisation, then the player built on it.
public struct PipelineProbe: Probe {
    struct Record: Encodable, Sendable {
        let step: String
        let detail: String
    }

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        await Self.drive(seconds: request.seconds, trace: trace, directory: directory)
    }

    @MainActor
    static func drive(seconds: Int, trace: TraceWriter, directory: URL) async {
        func note(_ step: String, _ detail: String) async {
            try? await trace.write(kind: "pipeline", Record(step: step, detail: detail))
        }
        let paths = AppPaths(root: directory, logs: directory)
        let store: MeetingStore
        do {
            store = MeetingStore(try AppDatabase(path: directory.appending(path: AppPaths.databaseFileName).path))
        } catch {
            await note("base", "\(error)")
            return
        }
        let presenter = ProbePresenter()
        let coordinator = MeetingCoordinator(
            store: store, paths: paths, recorders: LiveRecorderFactory(), presenter: presenter, detector: MeetingDetector(),
            clock: ContinuousTime.seconds, now: Date.init, availableBytes: { DiskGuard.availableBytes(at: directory) },
            deviceName: DeviceNames.name(forUID:), log: nil
        )
        await coordinator.user(.recordNow)
        try? await Task.sleep(for: .seconds(Double(seconds)))
        await coordinator.user(.stop)

        guard let row = (try? store.recent(limit: 1))?.first else {
            await note("ligne", "aucune réunion en base")
            return
        }
        await note("ligne", "\(row.status.rawValue) \(row.endReason?.rawValue ?? "-") « \(row.title) »")
        await note("présentateur", "alertes \(presenter.alerts) ; notices \(presenter.toasts.count)")
        let folder = paths.meetingFolder(row.id)
        do {
            let file = try MeetingFile.decoder.decode(MeetingFile.self, from: Data(contentsOf: folder.appending(path: "meeting.json")))
            let timeline = try MeetingTimeline.read(folder.appending(path: "timeline.jsonl"))
            await note("santé", "\(file.health)")
            let pieces = PlaybackPlan.pieces(
                folder: folder, timeline: timeline, moiSpans: file.moiSpans, originNanos: file.originNanos,
                segmentSeconds: MeetingRecorder.segmentSeconds
            )
            await note("morceaux", "\(pieces.count) : \(Dictionary(grouping: pieces, by: \.track).mapValues(\.count))")
            let player = try await MeetingPlayer(pieces: pieces)
            await note("lecteur", String(format: "%.1f s", player.durationSeconds))
        } catch {
            await note("lecture", "\(error)")
        }
    }
}

@MainActor
private final class ProbePresenter: MeetingPresenter {
    var alerts: [AppAlert] = []
    var toasts: [Toast] = []
    func showPrompt(title: String, deadline: Date) {}
    func hidePrompt() {}
    func show(_ toast: Toast) { toasts.append(toast) }
    func show(_ alert: AppAlert) { alerts.append(alert) }
    func update(_ status: RecorderStatus) {}
    func retitle(_ title: String) {}
}
