import Dictation
import Foundation

/// How a dictation ended, said in the window before it closes (21/11).
enum DictationOutcome: Equatable, Sendable {
    /// The text went where Paul was writing; the app by its name, and the text itself.
    case pasted(app: String?, text: String)
    /// Without the Accessibility, the text is only in the clipboard.
    case copied(text: String)
    /// Nothing was said, or Whisper heard nothing.
    case nothing
    /// The key was pressed while the Dictée could not listen: why.
    case notReady(String)
    case problem(String)
}

/// The Dictée's state, as the window needs it.
struct DictationWindowState: Equatable, Sendable {
    var phase: DictationService.Phase
    /// The microphone gives sound: Paul can talk.
    var micOpen = false
    /// Whisper is loaded: the final text can be written at once.
    var whisperLoaded = true
    /// The words as they come.
    var partial = ""
    /// Whether Paul wants to see his words as they come (Réglages › Dictée).
    var liveText = true
    /// The final writing's progress, 0 to 1.
    var progress: Double = 0
    var outcome: DictationOutcome?
    /// Seconds before a long silence finishes the dictation, once it is near.
    var silenceLeft: Int?
    var mode: KeyGesture.Mode = .toggle
    /// The key's name: « ⌥ droite ».
    var key = "⌥ droite"
}

/// What the Dictée's window says at each moment (21/11, Paul: « beaucoup plus expliqué, beaucoup plus propre ») : one
/// line that names what is happening, his words, and what to press. Pure: the state in, the words out.
struct DictationWindowContent: Equatable, Sendable {
    enum Mark: Equatable, Sendable {
        /// The microphone is opening: nothing is heard yet.
        case opening
        case listening
        /// Whisper writes the final text.
        case writing
        case done
        /// Something to know, that is not a failure.
        case notice
        case problem
    }

    var mark: Mark
    /// What is happening, in a few words.
    var title: String
    /// Paul's words, as they come, or the text that was pasted.
    var words: String?
    /// What stands where the words will be.
    var placeholder: String?
    /// The final writing's progress, 0 to 1; nil: no bar.
    var progress: Double?
    /// What to press, or what comes next.
    var hint: String?

    init(_ state: DictationWindowState) {
        let words = state.partial.isEmpty ? nil : state.partial
        if let outcome = state.outcome, state.phase != .listening, state.phase != .writing {
            switch outcome {
            case .pasted(let app, let text):
                self.init(mark: .done, title: app.map { "Collé dans \($0)" } ?? "Collé", words: text)
            case .copied(let text):
                self.init(mark: .done, title: "Copié : colle-le avec ⌘V", words: text,
                          hint: "Donne l'Accessibilité à hub dans Réglages › Dictée : il collera seul")
            case .nothing:
                self.init(mark: .notice, title: "Je n'ai rien entendu", hint: "Le micro se choisit dans Réglages › Dictée")
            case .notReady(let why):
                self.init(mark: .notice, title: why, hint: "Réessaie dans un instant")
            case .problem(let why):
                self.init(mark: .problem, title: why)
            }
            return
        }
        switch state.phase {
        case .listening where !state.micOpen:
            self.init(mark: .opening, title: "Le micro s'ouvre…", hint: Self.keys(state))
        case .listening:
            let quiet = state.silenceLeft.map { "Silence : je finis dans \($0) s" }
            self.init(mark: .listening, title: "Je t'écoute", words: state.liveText ? words : nil,
                      placeholder: state.liveText ? "Parle : tes mots s'écrivent ici." : "Parle, puis appuie de nouveau.",
                      hint: quiet ?? Self.keys(state))
        case .writing:
            // « Je relis » read as « je réécris » (Paul, 21/11): nothing is rewritten, the last words are being written.
            self.init(mark: .writing, title: state.whisperLoaded ? "J'écris tes derniers mots…" : "Whisper se charge, puis j'écris…",
                      words: state.liveText ? words : nil, progress: state.whisperLoaded ? min(1, max(0, state.progress)) : nil,
                      hint: "Le texte arrive là où tu écrivais")
        case .starting:
            self.init(mark: .notice, title: "La Dictée démarre…", hint: "Réessaie dans un instant")
        case .failed(let why):
            self.init(mark: .problem, title: why)
        case .ready:
            self.init(mark: .notice, title: "Prête", hint: Self.start(state))
        }
    }

    init(mark: Mark, title: String, words: String? = nil, placeholder: String? = nil, progress: Double? = nil, hint: String? = nil) {
        self.mark = mark
        self.title = title
        self.words = words
        self.placeholder = placeholder
        self.progress = progress
        self.hint = hint
    }

    /// What finishes and what cancels, by the way the key works.
    static func keys(_ state: DictationWindowState) -> String {
        switch state.mode {
        case .toggle, .hybrid: "\(state.key) pour finir · Échap pour annuler"
        case .hold: "Relâche pour finir · Échap pour annuler"
        }
    }

    static func start(_ state: DictationWindowState) -> String {
        switch state.mode {
        case .toggle, .hybrid: "\(state.key) pour parler"
        case .hold: "Tiens \(state.key) pour parler"
        }
    }
}

/// What a dictation took, one line in the day's log (21/11, after two versions that looked fast here and slow with Paul's
/// voice): times only, never a word, never the app.
struct DictationTiming: Codable, Equatable, Sendable {
    var at = Date()
    /// From the key to the microphone's first sound, in ms.
    var microphone: Int?
    /// From the microphone's first sound to the first words on the screen, in ms.
    var firstWords: Int?
    /// How many times the words changed on the screen while Paul talked.
    var updates = 0
    /// From the press that finishes to the text, in ms.
    var final: Int?
    /// Seconds of sound, and characters written.
    var seconds = 0.0
    var characters = 0
    /// How it ended: collé, copié, rien, annulé, échec.
    var end = ""

    /// One line of JSON, the keys in order.
    var line: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// Appends the line to `dictee-AAAAMMJJ.jsonl` in the folder; silent when it cannot.
    func write(in folder: URL?) {
        guard let folder else { return }
        let day = at.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        let file = folder.appending(path: "dictee-\(day).jsonl")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file)
        }
    }
}
