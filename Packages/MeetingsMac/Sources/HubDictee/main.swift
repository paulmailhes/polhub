import AudioCapture
import Compute
import Dictation
import Foundation
import Transcription

/// `hub-dictee`: the Dictée's ear (20/11). Launched by the app while the Dictée is installed, it listens to the
/// microphone on « commencer », says the words as they come, and the whole text on « finir ». One line of JSON per order
/// on its input, per news on its output (`DictationWire`). It dies with the app that launched it.
///
/// 21/11 (Paul: « dès que j'appuie, ça commence ») : it takes its orders from its first second — Whisper loads behind,
/// and a dictation said meanwhile is written as soon as it is there. Its files: `Microphone` (the sound), `Session` (one
/// dictation), `Whisper` (one call at a time), `Sounds` (files).
setenv("HF_HUB_OFFLINE", "1", 1)
guard getppid() != 1 else { exit(0) }
let parentWatch = DispatchSource.makeProcessSource(identifier: getppid(), eventMask: .exit, queue: .global())
// Sendable: run on a queue of its own, never the main actor's (a closure of the main actor stopped hub-dictee with a
// trap instead of leaving, 20/11).
parentWatch.setEventHandler { @Sendable in exit(0) }
parentWatch.resume()

let output = FileHandle.standardOutput
let outputLock = NSLock()
@Sendable func emit(_ event: DictationEvent) {
    guard let line = try? DictationWire.line(event) else { return }
    outputLock.withLock { output.write(Data((line + "\n").utf8)) }
}

let locations = ModelLocations.standard
let missing = locations.missing()
guard missing.isEmpty else {
    emit(.failed("Modèles absents : " + missing.joined(separator: ", ") + "."))
    exit(1)
}

let whisper = WhisperBox()
// Whisper loads (about twenty seconds) while the orders are already taken.
Task.detached {
    do {
        // The encoder on the GPU: a text in 0,75 s instead of 1,4 s (measured 21/11 on the M3 Max).
        let engine = try await WhisperEngine(locations: locations, encoderOnGPU: true)
        // Three seconds of a low tone: one real pass, so the first text does not pay for the warm-up (4 to 5 s on the
        // GPU, measured; a single second of silence did not even reach the encoder).
        let tone = (0..<48_000).map { Float(sin(Double($0) * 0.05)) * 0.05 }
        _ = try? await engine.dictate(tone, language: "fr", prompt: "", long: false)
        await whisper.loaded(engine)
        emit(.ready)
    } catch {
        emit(.failed("Whisper ne se charge pas : relance hub."))
        exit(1)
    }
}

/// The orders, one at a time, in the order they came.
actor Conductor {
    private let whisper: WhisperBox
    private var session: Session?
    private var source: (any SoundSource)?
    private var pump: Task<Void, Never>?

    init(whisper: WhisperBox) {
        self.whisper = whisper
    }

    func handle(_ command: DictationCommand) async {
        switch command {
        case .start(let options):
            await start(options)
        case .stop:
            await stop(cancelled: false)
        case .cancel:
            await stop(cancelled: true)
        case .file(let id, let path, let options):
            // Aside: the key stays free while a file is written.
            let whisper = whisper
            Task.detached { await Conductor.transcribe(id: id, path: path, options: options, whisper: whisper) }
        }
    }

    private func start(_ options: DictationListening) async {
        // A « commencer » without a « finir »: the dictation before is given up.
        if session != nil { await stop(cancelled: true) }
        let source: any SoundSource
        do {
            if let path = options.source {
                source = try PlayedFile(path: path)
            } else if let device = Microphone.choose(options.microphones) {
                source = try Microphone(device: device)
            } else {
                emit(.failed("Aucun micro n'est branché."))
                return
            }
        } catch {
            emit(.failed("Le micro ne s'ouvre pas. Choisis-en un autre dans Réglages › Dictée."))
            return
        }
        do {
            // Core Audio may block, a Bluetooth microphone takes its time: never on a thread that must answer.
            try await Task.detached { try source.start() }.value
        } catch {
            Task.detached { source.stop() }
            emit(.failed("Le micro met trop de temps à s'ouvrir. Réessaie, ou choisis-en un autre dans Réglages › Dictée."))
            return
        }
        let session = Session(options: options, whisper: whisper)
        self.session = session
        self.source = source
        pump = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(40))
                let heard = source.drain()
                if !heard.isEmpty { await session.hear(heard) }
            }
        }
    }

    /// The microphone closed; what it still held joins the dictation; then its text.
    private func stop(cancelled: Bool) async {
        guard let session, let source else { return }
        self.session = nil
        self.source = nil
        pump?.cancel()
        await pump?.value
        pump = nil
        await Task.detached { source.stop() }.value
        let rest = source.drain()
        if !rest.isEmpty { await session.hear(rest) }
        await session.finish(cancelled: cancelled)
    }

    /// A file of sound or a video, or a kept sound written again.
    static func transcribe(id: String, path: String, options: DictationListening, whisper: WhisperBox) async {
        let heard: [Float]
        do {
            heard = try read(path)
        } catch {
            emit(.fileFailed(id: id, reason: "Ce fichier n'a pas pu être lu : hub lit les sons et les vidéos que lit QuickTime."))
            return
        }
        guard heard.count > 4_000 else {
            emit(.fileFailed(id: id, reason: "Il n'y a presque rien à entendre dans ce fichier."))
            return
        }
        do {
            let text = try await whisper.run { engine in try await Session.write(engine, heard, options) }
            emit(.transcribed(id: id, text: text, seconds: Double(heard.count) / 16_000))
        } catch {
            emit(.fileFailed(id: id, reason: "Whisper n'a pas pu écrire ce fichier. Réessaie."))
        }
    }
}

let conductor = Conductor(whisper: whisper)
// The orders are read on a thread of their own: reading waits, and nothing else must.
let orders = AsyncStream<DictationCommand> { continuation in
    let reader = Thread {
        while let line = readLine(strippingNewline: true) {
            if let command = try? DictationWire.read(DictationCommand.self, line) { continuation.yield(command) }
        }
        continuation.finish()
    }
    reader.name = "orders"
    reader.start()
}
emit(.hello)
for await command in orders {
    await conductor.handle(command)
}
exit(0)
