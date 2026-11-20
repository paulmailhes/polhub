import Compute
import Dictation
import Foundation

/// Characters written so far by a call to Whisper, window by window: a long recording is written by several at once.
final class WrittenCount: @unchecked Sendable {
    private var windows: [Int: Int] = [:]
    private let lock = NSLock()

    func update(window: Int, characters: Int) -> Int {
        lock.withLock {
            windows[window] = characters
            return windows.values.reduce(0, +)
        }
    }
}

/// One dictation, from its first sound to its text (21/11, Paul: « que je voie ce que je suis en train de dire… et que
/// ça écrive direct »).
///
/// - The first sound says « je t'écoute » (`listening`): until then the microphone is opening.
/// - While Paul talks, Whisper writes what he has said so far, again and again: his words on the screen.
/// - Once he has stopped talking, the pass that follows holds everything: when he presses the key, the final text is
///   there, or well on its way. If he talks again, that text is only the words on the screen.
/// - Nothing said, nothing written: Whisper is not asked to hear a silence (it invents « Merci. »).
actor Session {
    /// Up to here, one pass of Whisper holds the whole dictation; beyond, a pass only writes its last seconds, for the
    /// screen, and the final text is written by several windows at the end.
    static let wholeLimit = 16_000 * 28
    /// A new pass when this much voice was said since the one before, in samples (0,4 s)…
    static let freshVoice = 6_400
    /// …or as soon as Paul has stopped for this long, in seconds: the pass that holds everything.
    static let pauseBeforePass = 0.25

    /// A pass of Whisper over what was said so far.
    private struct Pass {
        /// Where the listening was when it started.
        let mark: VoiceGate.Mark
        /// It heard the dictation from its start: its text can be the final one.
        let whole: Bool
        /// Raised when its text is no use any more: Whisper stops writing it.
        let dropped: StopFlag
        /// Raised when the key was pressed while it was being written: its progress is then shown.
        let awaited: StopFlag
        let task: Task<String?, Never>
    }

    private let options: DictationListening
    private let whisper: WhisperBox
    private var samples: [Float] = []
    private var open = true
    private var announced = false
    private var lastLevel = ContinuousClock.now - .seconds(1)
    private var gate = VoiceGate()
    /// The longest text a pass wrote: to gauge the final writing's progress.
    private var writtenCharacters = 0
    private var pass: Pass?
    private var passRunning = false
    /// The voice heard when the latest pass started, in samples.
    private var voicedAtPass = 0

    init(options: DictationListening, whisper: WhisperBox) {
        self.options = options
        self.whisper = whisper
    }

    /// A piece of sound from the microphone, 16 kHz mono.
    func hear(_ piece: [Float]) {
        guard open, !piece.isEmpty else { return }
        samples += piece
        if !announced {
            announced = true
            emit(.listening)
        }
        // The voice or the silence, by 50 ms.
        var start = 0
        while start < piece.count {
            let end = min(piece.count, start + 800)
            gate.hear(Array(piece[start..<end]))
            start = end
        }
        // The level for the curve, twenty times a second at most.
        let now = ContinuousClock.now
        if now - lastLevel >= .milliseconds(50) {
            lastLevel = now
            emit(.level(Double(min(1, VoiceGate.loudness(piece) * 8))))
        }
        considerPass()
    }

    /// Whisper is free and Paul said something new: a pass over what he has said so far.
    private func considerPass() {
        // Paul has just stopped, and the pass under way started before his last words: it is dropped, so that the one
        // that holds everything starts sooner.
        if passRunning, let pass, !pass.dropped.isStopped, gate.silence >= Self.pauseBeforePass, gate.voiced > voicedAtPass {
            pass.dropped.stop()
        }
        guard open, !passRunning, gate.voicedSeconds >= 0.3 else { return }
        let fresh = gate.voiced - voicedAtPass
        guard fresh > 0, fresh >= Self.freshVoice || gate.silence >= Self.pauseBeforePass else { return }
        let whole = samples.count <= Self.wholeLimit
        let heard = whole ? samples : Array(samples.suffix(Self.wholeLimit))
        let options = options, whisper = whisper, expected = expectedCharacters
        let dropped = StopFlag(), awaited = StopFlag(), count = WrittenCount()
        passRunning = true
        voicedAtPass = gate.voiced
        let task = Task<String?, Never> { [weak self] in
            let text = try? await whisper.run { engine in
                guard whole else {
                    // Its last seconds only: the words for the screen.
                    return try await engine.dictate(heard, language: options.language, prompt: options.prompt, long: false) { _, _ in
                        !dropped.isStopped
                    }
                }
                // The whole dictation, written as the final text will be.
                return try await Session.write(engine, heard, options) { window, text in
                    if awaited.isStopped { emit(.progress(Session.progress(count.update(window: window, characters: text.count), of: expected))) }
                    return !dropped.isStopped
                }
            }
            await self?.passEnded(text, dropped: dropped)
            return dropped.isStopped ? nil : text
        }
        pass = Pass(mark: gate.mark, whole: whole, dropped: dropped, awaited: awaited, task: task)
    }

    private func passEnded(_ text: String?, dropped: StopFlag) {
        passRunning = false
        guard !dropped.isStopped, let text, !text.isEmpty else { return }
        writtenCharacters = max(writtenCharacters, text.count)
        if open { emit(.partial(text)) }
    }

    /// The microphone is closed: the text; or nothing, when the dictation is given up.
    func finish(cancelled: Bool) async {
        open = false
        let heard = samples
        let seconds = Double(heard.count) / 16_000
        if cancelled {
            pass?.dropped.stop()
            return
        }
        guard heard.count > 4_000, gate.heardVoice else {
            pass?.dropped.stop()
            emit(.final(text: "", seconds: seconds))
            return
        }
        if let path = options.keepSoundAt {
            Task.detached(priority: .utility) { keep(heard, at: path) }
        }
        // The pass that started after Paul's last word holds everything: its text is the final one.
        if let pass, pass.whole, gate.nothingSince(pass.mark) {
            pass.awaited.stop()
            if let text = await pass.task.value, !text.isEmpty {
                emit(.progress(1))
                emit(.final(text: text, seconds: seconds))
                return
            }
        }
        pass?.dropped.stop()
        let options = options, expected = expectedCharacters, count = WrittenCount()
        do {
            let text = try await whisper.run { engine in
                try await Session.write(engine, heard, options) { window, text in
                    emit(.progress(Session.progress(count.update(window: window, characters: text.count), of: expected)))
                    return true
                }
            }
            emit(.progress(1))
            emit(.final(text: text, seconds: seconds))
        } catch let failure as WhisperUnavailable {
            emit(.failed(failure.description))
        } catch {
            emit(.failed("Whisper n'a pas pu écrire ce que tu as dit. Réessaie."))
        }
    }

    /// How long the final text should be: as long as the words on the screen, or about fourteen characters a second of
    /// voice.
    private var expectedCharacters: Int {
        max(writtenCharacters, Int(gate.voicedSeconds * 14), 1)
    }

    /// Never full before the text is there.
    static func progress(_ written: Int, of expected: Int) -> Double {
        min(0.97, Double(written) / Double(max(expected, 1)))
    }

    /// The whole text; with paragraphs after the long pauses when Paul wants them, and when there are some. `onText`:
    /// what is written so far, window by window; false stops the writing.
    static func write(_ engine: WhisperEngine, _ heard: [Float], _ options: DictationListening,
                      onText: (@Sendable (_ window: Int, _ text: String) -> Bool)? = nil) async throws -> String {
        let long = heard.count > wholeLimit
        guard let pause = options.paragraphPause else {
            return try await engine.dictate(heard, language: options.language, prompt: options.prompt, long: long, onText: onText)
        }
        let breaks = DictationParagraphs.pauses(heard, longerThan: pause)
        guard !breaks.isEmpty else {
            return try await engine.dictate(heard, language: options.language, prompt: options.prompt, long: long, onText: onText)
        }
        let pieces = try await engine.dictatePieces(heard, language: options.language, prompt: options.prompt, long: long, onText: onText)
        return DictationParagraphs.join(pieces.map { DictationParagraphs.Piece(text: $0.text, start: $0.start, end: $0.end) }, breaks: breaks)
    }
}
