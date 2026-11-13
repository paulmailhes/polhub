import Foundation
import Observability
import Recording

/// `--probe record`: the meeting recorder of step 1, as a meeting in Dia, with its inaudible check. The
/// meeting folder is the probe's folder; the recorder's events go to the probe's trace.
public struct RecordProbe: Probe {
    struct EventRecord: Encodable, Sendable {
        let event: String
    }

    public init() {}

    public func run(_ request: ProbeRequest, trace: TraceWriter, directory: URL) async {
        let recorder: MeetingRecorder
        do {
            recorder = try MeetingRecorder(folder: directory, mode: .dia, selfTestAmplitude: SystemAudioSelfTest.inaudibleAmplitude)
        } catch {
            try? await trace.write(kind: "record-error", EventRecord(event: "\(error)"))
            return
        }
        let listener = Task {
            for await event in recorder.events {
                try? await trace.write(kind: "recorder-event", EventRecord(event: "\(event)"))
            }
        }
        await recorder.start()
        _ = await Self.pause(Double(request.seconds))
        await recorder.stop()
        await listener.value
    }
}
