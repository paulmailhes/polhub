import Compute
import Foundation
import Transcription

/// `transcriptor-calcul '<CalculRequest en JSON>'`: transcribes one meeting, one JSON message per line on
/// the standard output. Launched by the app outside meetings, stopped by a signal as soon as a Meet shows.
setenv("HF_HUB_OFFLINE", "1", 1)

// The calcul dies with the app that launched it: an orphan would compute during a meeting, out of the
// queue's sight (review, Important 4).
guard getppid() != 1 else { exit(0) }
let parentWatch = DispatchSource.makeProcessSource(identifier: getppid(), eventMask: .exit, queue: .global())
parentWatch.setEventHandler { exit(0) }
parentWatch.resume()
let output = FileHandle.standardOutput

@Sendable func emit(_ message: CalculMessage) {
    guard let line = try? JSONEncoder().encode(message) else { return }
    output.write(line + Data("\n".utf8))
}

func fail(_ message: String) -> Never {
    emit(.failed(message))
    exit(1)
}

guard CommandLine.arguments.count == 2, let request = try? JSONDecoder().decode(CalculRequest.self, from: Data(CommandLine.arguments[1].utf8)) else {
    fail("Usage : transcriptor-calcul '<requête JSON>'")
}
let locations = ModelLocations.standard
let missing = locations.missing()
guard missing.isEmpty else { fail("Modèles absents : " + missing.joined(separator: ", ") + ".") }

do {
    let detector = try SileroDetector(model: locations.sileroModel)
    let engine = try await WhisperEngine(locations: locations)
    try await TranscriptionRun(request: request, detector: detector, engine: engine, emit: emit).run()
    exit(0)
} catch {
    fail("\(error)")
}
