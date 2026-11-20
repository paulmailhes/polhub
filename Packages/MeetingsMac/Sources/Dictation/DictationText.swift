import Foundation
import Transcription

/// A correction of the memory (20/11): what Whisper hears, and what Paul means.
public struct DictationReplacement: Codable, Equatable, Sendable {
    public var heard: String
    public var written: String

    public init(heard: String, written: String) {
        self.heard = heard
        self.written = written
    }
}

/// What is pasted (20/11): Paul's words, well punctuated, without the hesitations, with his corrections; nothing when
/// Whisper invented a sentence in the silence.
public enum DictationText {
    /// The hesitations of spoken French, as whole words.
    public static let fillers = ["euh", "heu", "hum", "hmm", "bah"]

    public static func clean(_ raw: String, replacements: [DictationReplacement]) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !TranscriptChecks.isPhantom(text) else { return "" }
        // A hesitation and the commas around it: « je voudrais, euh, un devis » is « je voudrais un devis ».
        let words = fillers.joined(separator: "|")
        text = text.replacingOccurrences(of: #"(?i),?\s*(?<![\p{L}\p{N}])(\#(words))(?![\p{L}\p{N}]),?"#, with: "", options: .regularExpression)
        for replacement in replacements where !replacement.heard.trimmingCharacters(in: .whitespaces).isEmpty {
            let heard = NSRegularExpression.escapedPattern(for: replacement.heard.trimmingCharacters(in: .whitespaces))
            let written = NSRegularExpression.escapedTemplate(for: replacement.written)
            text = text.replacingOccurrences(of: #"(?i)(?<![\p{L}\p{N}])\#(heard)(?![\p{L}\p{N}])"#, with: written, options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[,;\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // The sentence starts with a capital, unless it starts with a word of the memory written in lowercase (« hub »).
        guard let first = text.first, first.isLowercase,
              !replacements.contains(where: { $0.written.first?.isLowercase == true && text.lowercased().hasPrefix($0.written.lowercased()) })
        else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// The words of the memory, given to Whisper as its prompt (20/11): each once, the first ones first, within a length.
public enum DictationPrompt {
    /// About a hundred words: Whisper takes 224 tokens of prompt.
    public static let limit = 600

    public static func make(_ words: [String], limit: Int = limit) -> String {
        var seen: Set<String> = []
        var kept: [String] = []
        var length = 0
        for word in words.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !word.isEmpty {
            guard seen.insert(word.lowercased()).inserted else { continue }
            let added = (kept.isEmpty ? 0 : 2) + word.count
            guard length + added <= limit else { break }
            kept.append(word)
            length += added
        }
        return kept.joined(separator: ", ")
    }
}
