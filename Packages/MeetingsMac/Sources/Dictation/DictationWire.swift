import Foundation

/// How the helper listens (20/11 in the evening): the language, the memory's words, and what Paul chose in Réglages.
public struct DictationListening: Codable, Equatable, Sendable {
    /// nil: Whisper finds the language.
    public var language: String?
    /// The memory's words, as Whisper's prompt.
    public var prompt: String
    /// A paragraph after a silence this long, in seconds; nil: never.
    public var paragraphPause: Double?
    /// The microphone, by its Core Audio UID; nil: the system's.
    public var microphone: String?
    /// Where the sound is kept (AAC); nil: it is not.
    public var keepSoundAt: String?

    public init(language: String?, prompt: String, paragraphPause: Double? = nil, microphone: String? = nil, keepSoundAt: String? = nil) {
        self.language = language
        self.prompt = prompt
        self.paragraphPause = paragraphPause
        self.microphone = microphone
        self.keepSoundAt = keepSoundAt
    }
}

/// What the app asks the helper `hub-dictee` (20/11), one line of JSON on its standard input.
public enum DictationCommand: Codable, Equatable, Sendable {
    /// Listen to the microphone.
    case start(DictationListening)
    /// Stop listening and give the final text.
    case stop
    /// Stop listening and give nothing.
    case cancel
    /// A file of sound or a video (« Transcrire un fichier », a kept sound written again): its text, under `id`.
    case file(id: String, path: String, listening: DictationListening)
}

/// What the helper tells the app, one line of JSON on its standard output.
public enum DictationEvent: Codable, Equatable, Sendable {
    /// Whisper is loaded: the key may be pressed.
    case ready
    /// The voice's level, 0 to 1, for the waveform.
    case level(Double)
    /// The words said so far.
    case partial(String)
    /// The text of the whole recording, and how long it lasted.
    case final(text: String, seconds: Double)
    /// A file's text, and how long its sound lasts.
    case transcribed(id: String, text: String, seconds: Double)
    /// A file that could not be read or written.
    case fileFailed(id: String, reason: String)
    case failed(String)
}

public enum DictationWire {
    public static func line(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    public static func read<Value: Decodable>(_ type: Value.Type, _ line: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(line.utf8))
    }
}
