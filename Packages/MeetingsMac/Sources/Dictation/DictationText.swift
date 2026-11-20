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

/// What is done to the words (Réglages › Dictée, 20/11 in the evening): each rule can be turned off.
public struct DictationRules: Equatable, Sendable {
    /// The « euh », « hum », « bah » taken out.
    public var fillers: Bool
    /// « à la ligne », « virgule », « point d'interrogation »… said, written as signs.
    public var spokenPunctuation: Bool
    /// The numbers in digits, from ten or before a unit.
    public var digits: Bool
    /// One sentence ends without its period, as in a chat.
    public var dropFinalPeriod: Bool

    public init(fillers: Bool, spokenPunctuation: Bool, digits: Bool, dropFinalPeriod: Bool) {
        self.fillers = fillers
        self.spokenPunctuation = spokenPunctuation
        self.digits = digits
        self.dropFinalPeriod = dropFinalPeriod
    }

    /// The first version's: only the « euh » go.
    public static let plain = DictationRules(fillers: true, spokenPunctuation: false, digits: false, dropFinalPeriod: false)
    /// Réglages' defaults: everything Paul chose on 20/11.
    public static let standard = DictationRules(fillers: true, spokenPunctuation: true, digits: true, dropFinalPeriod: true)
}

/// What is pasted (20/11): Paul's words, well punctuated, without the hesitations, with his corrections; nothing when
/// Whisper invented a sentence in the silence. The paragraphs the helper made (`\n\n`) stay.
public enum DictationText {
    /// The hesitations of spoken French, as whole words.
    public static let fillers = ["euh", "heu", "hum", "hmm", "bah"]

    public static func clean(_ raw: String, replacements: [DictationReplacement], rules: DictationRules = .plain) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !TranscriptChecks.isPhantom(text) else { return "" }
        if rules.fillers {
            // A hesitation and the commas around it: « je voudrais, euh, un devis » is « je voudrais un devis ».
            let words = fillers.joined(separator: "|")
            text = text.replacingOccurrences(of: #"(?i),?[ \t]*(?<![\p{L}\p{N}])(\#(words))(?![\p{L}\p{N}]),?"#, with: "", options: .regularExpression)
        }
        for replacement in replacements where !replacement.heard.trimmingCharacters(in: .whitespaces).isEmpty {
            let heard = NSRegularExpression.escapedPattern(for: replacement.heard.trimmingCharacters(in: .whitespaces))
            let written = NSRegularExpression.escapedTemplate(for: replacement.written)
            text = text.replacingOccurrences(of: #"(?i)(?<![\p{L}\p{N}])\#(heard)(?![\p{L}\p{N}])"#, with: written, options: .regularExpression)
        }
        if rules.digits { text = DictationNumbers.digits(text) }
        if rules.spokenPunctuation { text = SpokenPunctuation.apply(text) }
        text = text.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+([.,)])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\([ \t]+"#, with: "(", options: .regularExpression)
            .replacingOccurrences(of: #"^[,;\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = capitalized(text, replacements: replacements)
        if rules.dropFinalPeriod { text = withoutFinalPeriod(text) }
        return text
    }

    /// Each line starts with a capital, and what follows a « ? » or a « ! » — unless it starts with a word of the memory
    /// written in lowercase (« hub »).
    static func capitalized(_ text: String, replacements: [DictationReplacement]) -> String {
        let lowercase = replacements.map(\.written).filter { $0.first?.isLowercase == true }.map { $0.lowercased() }
        var result = ""
        var capitalize = true
        var rest = Substring(text)
        while let character = rest.first {
            if capitalize, character.isLetter {
                let keep = lowercase.contains { rest.lowercased().hasPrefix($0) }
                result.append(keep || !character.isLowercase ? String(character) : character.uppercased())
                capitalize = false
            } else {
                result.append(character)
                if character == "\n" || ((character == "?" || character == "!") && rest.dropFirst().first == " ") { capitalize = true }
                else if !character.isWhitespace && !"«(\"".contains(character) { capitalize = false }
            }
            rest = rest.dropFirst()
        }
        return result
    }

    /// One sentence, on one line, ends without its period; « … » and « ... » stay.
    static func withoutFinalPeriod(_ text: String) -> String {
        guard text.hasSuffix("."), !text.hasSuffix(".."), !text.contains("\n"),
              text.dropLast().range(of: #"[.?!…]\s"#, options: .regularExpression) == nil else { return text }
        return String(text.dropLast())
    }
}

/// « à la ligne », « virgule », « point d'interrogation »… said aloud, written as signs (20/11 in the evening). « deux
/// points » stays words: « j'ai deux points à voir ».
enum SpokenPunctuation {
    /// What Whisper may have put before a word said: spaces, and a comma or a period.
    private static let before = #"[ \t]*[,.;:]?[ \t]*"#
    /// After it: a comma; a period too after a line break, never after a sign (« fermez les guillemets. »).
    private static let after = #"[ \t]*,?[ \t]*"#
    private static let afterBreak = #"[ \t]*[,.;:]?[ \t]*"#

    static let signs: [(said: String, written: String)] = [
        ("point à la ligne", ".\n"),
        ("nouveau paragraphe", "\n\n"),
        ("retour à la ligne", "\n"),
        ("à la ligne", "\n"),
        ("point d['’]interrogation", " ? "),
        ("point d['’]exclamation", " ! "),
        ("point[- ]virgule", " ; "),
        ("virgule", ", "),
        ("(?:ouvrez|ouvrir|ouvre) les guillemets", " « "),
        ("(?:fermez|fermer|ferme) les guillemets", " » "),
        ("(?:ouvrez|ouvrir|ouvre) la parenthèse", " ("),
        ("(?:fermez|fermer|ferme) la parenthèse", ") "),
    ]

    static func apply(_ text: String) -> String {
        var text = text
        for sign in signs {
            let trailing = sign.written.hasSuffix("\n") ? afterBreak : after
            text = text.replacingOccurrences(of: "(?i)" + before + #"(?<![\p{L}\p{N}])"# + sign.said + #"(?![\p{L}\p{N}])"# + trailing,
                                             with: NSRegularExpression.escapedTemplate(for: sign.written), options: .regularExpression)
        }
        return text.replacingOccurrences(of: #"«[ \t]+"#, with: "« ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]+»"#, with: " »", options: .regularExpression)
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
