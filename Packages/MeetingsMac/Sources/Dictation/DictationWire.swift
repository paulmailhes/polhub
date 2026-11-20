import Foundation

/// What the app asks the helper `hub-dictee` (20/11), one line of JSON on its standard input.
public enum DictationCommand: Codable, Equatable, Sendable {
    /// Listen to the microphone, with the memory's words as Whisper's prompt.
    case start(language: String?, prompt: String)
    /// Stop listening and give the final text.
    case stop
    /// Stop listening and give nothing.
    case cancel
    /// A file of sound, for the measures: its text, as if it had been said.
    case file(path: String, language: String?, prompt: String)
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
