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

/// Raised when the key was pressed while a pass was being written: its progress is then shown, on its share of the bar.
final class Awaited: @unchecked Sendable {
    private var bar: (from: Double, span: Double)?
    private let lock = NSLock()

    func show(from: Double = 0, span: Double = 1) {
        lock.withLock { bar = (from, span) }
    }

    /// Where `progress` falls on the bar; nil while nobody waits for this pass.
    func place(_ progress: Double) -> Double? {
        lock.withLock { bar.map { $0.from + $0.span * progress } }
    }
}

/// One dictation, from its first sound to its text (21/11, Paul: « que je voie ce que je suis en train de dire… et que
/// ça écrive direct »).
///
/// - The first sound says « je t'écoute » (`listening`): until then the microphone is opening.
/// - While Paul talks, Whisper writes what he has said so far, again and again: his words on the screen.
/// - Once he has stopped talking, the pass that follows holds everything: when he presses the key, the final text is
///   there, or well on its way. If he talks again, that text is only the words on the screen.
/// - A long dictation is kept piece by piece (`DictationChunks`): once ten seconds are said, the pass that starts at a
///   pause keeps its text for good, and the passes after it only hear what came since. At the press, only the end is
///   left to write: the text comes as fast after a hundred seconds as after ten.
/// - Nothing said, nothing written: Whisper is not asked to hear a silence (it invents « Merci. »).
actor Session {
    /// Up to here since the last cut, one pass of Whisper holds it all; beyond, a pass only writes its last seconds, for
    /// the screen, and the end of the final text is written by several windows.
    static let wholeLimit = 16_000 * 28
    /// The voice the first pass waits for, and the first one after a cut, in seconds.
    static let firstVoice = 0.7
    /// A new pass when this much voice was said since the one before, in samples (0,4 s)…
    static let freshVoice = 6_400
    /// …or as soon as Paul has stopped for this long, in seconds: the pass that holds everything.
    static let pauseBeforePass = 0.25

    /// What a pass heard.
    private struct Heard: Sendable {
        /// From here to there, in samples from the start.
        let start: Int
        let end: Int
        /// Everything since the last cut: its text can be kept, or end the final one.
        let whole: Bool
        /// Its end falls in a silence: a clean cut.
        let atPause: Bool
        /// The voice heard when it started, in samples.
        let voiced: Int
        /// It heard up to the moment it started: its text goes on the screen. A pass that keeps the sound up to the last
        /// pause does not: the screen keeps the words it has until the next pass.
        var live = true
    }

    /// A pass of Whisper over what was said since the last cut.
    private struct Pass {
        /// Where the listening was when it started.
        let mark: VoiceGate.Mark
        let heard: Heard
        /// Raised when its text is no use any more: Whisper stops writing it.
        let dropped: StopFlag
        /// Set when the key was pressed while it was being written: its progress is then shown.
        let awaited: Awaited
        let task: Task<String?, Never>
    }

    private let options: DictationListening
    private let whisper: WhisperBox
    private var samples: [Float] = []
    private var open = true
    private var announced = false
    private var lastLevel = ContinuousClock.now - .seconds(1)
    private var gate = VoiceGate()
    /// What is kept of the dictation, and where it was cut.
    private var chunks = DictationChunks()
    /// The voice heard up to the last cut, in samples.
    private var voicedAtCut = 0
    /// The voice heard by each moment, 50 ms by 50 ms: how much was said before a cut.
    private var voiceLog: [(samples: Int, voiced: Int)] = []
    /// What the latest pass wrote after the last cut: the words on the screen after the kept ones.
    private var tail: String?
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
            voiceLog.append((gate.samples, gate.voiced))
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

    /// Whisper is free and Paul said something new: a pass over what he has said since the last cut.
    private func considerPass() {
        // A pass under way is never dropped while Paul talks, even at a pause: 0.64.0 dropped it at each quarter of a
        // second of silence, and with a real voice — which pauses — the words almost never reached the screen (Paul,
        // 21/11: « le texte, il s'affiche pas »). It is dropped only when the key is pressed and it holds too little.
        // The first pass waits for 0,7 s of voice, and so does the first after a cut: on less, Whisper often writes
        // nothing, and that pass is lost (measured 21/11: the first words at 1,9 to 2,8 s instead of 1,4 s).
        let sinceCut = Double(gate.voiced - voicedAtCut) / gate.rate
        guard open, !passRunning, sinceCut >= (tail == nil ? Self.firstVoice : 0.3) else { return }
        let fresh = gate.voiced - voicedAtPass
        guard fresh > 0, fresh >= Self.freshVoice || gate.silence >= Self.pauseBeforePass else { return }
        let start = chunks.base
        let atPause = gate.silence >= Self.pauseBeforePass
        var end = samples.count
        var live = true
        // Ten seconds since the last cut, and Paul is talking: this pass keeps them, up to his last pause.
        if !atPause, let cut = DictationChunks.cut(samples, from: start) {
            end = cut
            live = false
        }
        let whole = end - start <= Self.wholeLimit
        let heard = Heard(start: start, end: end, whole: whole, atPause: atPause || !live, voiced: voiced(at: end), live: live)
        let sound = Array(samples[(whole ? start : end - Self.wholeLimit)..<end])
        let options = options, whisper = whisper, expected = expectedCharacters
        let dropped = StopFlag(), awaited = Awaited(), count = WrittenCount()
        passRunning = true
        voicedAtPass = gate.voiced
        let task = Task<String?, Never>(priority: .userInitiated) { [weak self] in
            let text = try? await whisper.run { engine in
                guard whole else {
                    // Its last seconds only: the words for the screen.
                    return try await engine.dictate(sound, language: options.language, prompt: options.prompt, long: false) { _, _ in
                        !dropped.isStopped
                    }
                }
                // Everything since the last cut, written as the final text will be.
                return try await Session.write(engine, sound, options) { window, text in
                    if let place = awaited.place(Session.progress(count.update(window: window, characters: text.count), of: expected)) {
                        emit(.progress(place))
                    }
                    return !dropped.isStopped
                }
            }
            let written = dropped.isStopped ? nil : text
            await self?.passEnded(written, heard)
            return written
        }
        pass = Pass(mark: gate.mark, heard: heard, dropped: dropped, awaited: awaited, task: task)
    }

    private func passEnded(_ text: String?, _ heard: Heard) {
        passRunning = false
        guard let text, !text.isEmpty else { return }
        if heard.whole, keepText(text, heard) {
            tail = nil
        } else if heard.live {
            tail = text
        }
        // A pass that kept the sound up to the last pause leaves the screen as it is: Paul's words go on past its cut.
        if open, heard.live { emit(.partial(chunks.screen(with: tail))) }
    }

    /// The voice heard up to a moment, in samples.
    private func voiced(at sample: Int) -> Int {
        var low = 0, high = voiceLog.count
        while low < high {
            let middle = (low + high) / 2
            if voiceLog[middle].samples <= sample { low = middle + 1 } else { high = middle }
        }
        return low == 0 ? 0 : voiceLog[low - 1].voiced
    }

    /// Keeps a pass's text for good, when it can be (`DictationChunks.offer`).
    private func keepText(_ text: String, _ heard: Heard, always: Bool = false) -> Bool {
        guard chunks.offer(text, from: heard.start, to: heard.end, atPause: heard.atPause, always: always) else { return false }
        voicedAtCut = heard.voiced
        return true
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
        // The pass under way heard everything since the last cut. When Paul said nothing after it started, its text ends
        // the final one. When it ends in a pause and holds enough, it is kept, and only what came after is written.
        var from = 0.0
        if let pass, pass.heard.whole, pass.heard.start == chunks.base {
            let last = pass.heard.live && gate.nothingSince(pass.mark)
            if last || (pass.heard.atPause && pass.heard.end - pass.heard.start >= DictationChunks.length) {
                pass.awaited.show(span: last ? 1 : 0.6)
                if let text = await pass.task.value { _ = keepText(text, pass.heard, always: true) }
                // Kept here or as it ended: what comes after it has the rest of the bar.
                if !last, chunks.base == pass.heard.end { from = 0.6 }
            }
        }
        pass?.dropped.stop()
        let start = chunks.base
        guard start == 0 || gate.voiceEnd > start else {
            // Nothing said since the last cut: the text is all kept.
            emit(.progress(1))
            emit(.final(text: chunks.text(tail: nil, samples: heard, paragraphPause: options.paragraphPause), seconds: seconds))
            return
        }
        let rest = Array(heard[start...])
        let options = options, expected = expectedCharacters, count = WrittenCount(), chunks = chunks, offset = from
        do {
            let text = try await whisper.run { engine in
                try await Session.write(engine, rest, options) { window, text in
                    let progress = Session.progress(count.update(window: window, characters: text.count), of: expected)
                    emit(.progress(offset + (1 - offset) * progress))
                    return true
                }
            }
            emit(.progress(1))
            emit(.final(text: chunks.text(tail: text, samples: heard, paragraphPause: options.paragraphPause), seconds: seconds))
        } catch let failure as WhisperUnavailable {
            emit(.failed(failure.description))
        } catch {
            emit(.failed("Whisper n'a pas pu écrire ce que tu as dit. Réessaie."))
        }
    }

    /// How long the text after the last cut should be: as long as the words on the screen, or about fourteen characters a
    /// second of voice.
    private var expectedCharacters: Int {
        max(tail?.count ?? 0, Int(Double(gate.voiced - voicedAtCut) / gate.rate * 14), 1)
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
