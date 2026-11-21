import Foundation

/// A long dictation, written while it is said (21/11, Paul: « c'est trop lent… limite pas fonctionnel »: a dictation of
/// 100 s took 16,7 s after the press, Whisper writing it all again). Once ten seconds are said, the pass that starts at a
/// pause keeps what it wrote for good, and the passes after it hear only what came since: at the press, only the end is
/// left to write, however long the dictation.
public struct DictationChunks: Sendable, Equatable {
    /// A pass over this much sound since the last cut keeps its text, when it started at a pause: 10 s.
    public static let length = 16_000 * 10

    /// What is kept, piece by piece.
    public private(set) var texts: [String] = []
    /// Where each piece ends, in samples from the start.
    public private(set) var cuts: [Int] = []

    public init() {}

    /// Where what is not kept yet starts, in samples.
    public var base: Int { cuts.last ?? 0 }

    /// A pass heard the sound from `start` to `end` and wrote `text`. It is kept when it heard everything since the last
    /// cut and stopped at a pause, long enough; or, with `always`, at the press, when nothing better will come. True when
    /// it was kept.
    @discardableResult
    public mutating func offer(_ text: String, from start: Int, to end: Int, atPause: Bool, always: Bool = false) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard start == base, end > start, !text.isEmpty, always || (atPause && end - start >= Self.length) else { return false }
        texts.append(text)
        cuts.append(end)
        return true
    }

    /// Where to cut what is not kept yet, in samples from the start: in the middle of its last silence of `pause` seconds
    /// or more, when that leaves a piece of `length` before it; nil when there is none yet. A pass rarely starts right in
    /// a pause (measured 21/11: one pass follows another while Paul talks), so the cut is looked for in the sound.
    public static func cut(_ samples: [Float], from base: Int, rate: Double = 16_000, pause: Double = 0.3) -> Int? {
        guard base >= 0, samples.count - base > length else { return nil }
        let energies = DictationParagraphs.energies(Array(samples[base...]), rate: rate)
        guard energies.count > 1 else { return nil }
        let threshold = DictationParagraphs.threshold(energies)
        let size = Int(rate * DictationParagraphs.frame)
        let minimum = Int((pause / DictationParagraphs.frame).rounded(.up))
        var index = energies.count - 1
        while index >= 0 {
            while index >= 0, energies[index] >= threshold { index -= 1 }
            let last = index
            while index >= 0, energies[index] < threshold { index -= 1 }
            let first = index + 1
            guard last >= first, last - first + 1 >= minimum else { continue }
            let middle = base + (first + last + 1) / 2 * size
            // The silences before this one are even closer to the last cut.
            return middle - base >= length ? middle : nil
        }
        return nil
    }

    /// The words on the screen: what is kept, then what the latest pass wrote after it.
    public func screen(with tail: String?) -> String {
        (texts + [tail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The text of the dictation: the pieces kept, then `tail`, what was said after the last cut. A paragraph starts at a
    /// cut that fell in a pause of `paragraphPause` seconds or more, when Paul wants paragraphs.
    public func text(tail: String?, samples: [Float], rate: Double = 16_000, paragraphPause: Double?) -> String {
        var text = ""
        var pieces = texts.map(Optional.some) + [tail?.trimmingCharacters(in: .whitespacesAndNewlines)]
        pieces = pieces.filter { !($0?.isEmpty ?? true) }
        for (index, piece) in pieces.enumerated() {
            guard let piece else { continue }
            guard index > 0 else {
                text = piece
                continue
            }
            let cut = Double(cuts[index - 1]) / rate
            let long = paragraphPause.map { DictationParagraphs.silence(around: cut, in: samples, rate: rate) >= $0 } ?? false
            text = Self.joined(text, piece, separator: long ? "\n\n" : " ")
        }
        return text
    }

    /// Two pieces of text one after the other. Whisper starts each one with a capital letter: when the first does not end
    /// a sentence, the common word that starts the second takes its small letter back; a name keeps its capital.
    public static func joined(_ first: String, _ second: String, separator: String = " ") -> String {
        guard separator == " ", let last = first.trimmingCharacters(in: .whitespaces).last, !".!?…:»\"".contains(last),
              let word = second.split(separator: " ").first, let initial = word.first, initial.isUppercase else {
            return first + separator + second
        }
        let lowered = word.lowercased()
        let elided = lowered.firstIndex { $0 == "'" || $0 == "’" }.map { String(lowered[...$0]) }
        guard smallWords.contains(lowered.trimmingCharacters(in: .punctuationCharacters)) || elided.map(smallWords.contains) == true else {
            return first + separator + second
        }
        return first + separator + initial.lowercased() + second.dropFirst()
    }

    /// The French words that start a sentence as often as they go on one.
    static let smallWords: Set<String> = [
        "je", "j'", "j’", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "le", "la", "les", "l'", "l’", "un", "une",
        "des", "du", "de", "d'", "d’", "et", "ou", "mais", "donc", "car", "ni", "que", "qu'", "qu’", "qui", "quoi", "quand",
        "comme", "si", "s'", "s’", "ça", "ce", "c'", "c’", "cette", "ces", "cet", "en", "y", "à", "au", "aux", "dans", "sur",
        "sous", "pour", "par", "avec", "sans", "puis", "alors", "après", "avant", "parce", "pas", "plus", "moins", "très",
        "tout", "tous", "toute", "toutes", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos",
        "votre", "vos", "leur", "leurs", "est", "sont", "a", "ont", "faut", "va", "peut", "m'", "m’", "t'", "t’", "n'", "n’",
        "ne", "enfin", "aussi", "encore", "voilà", "bon", "ben", "oui", "non", "parfois", "toujours", "jamais", "même",
    ]
}
