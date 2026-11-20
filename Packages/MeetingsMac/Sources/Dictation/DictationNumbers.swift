import Foundation

/// Numbers in digits (20/11 in the evening, Paul): from ten, or before a unit; « un » and « une » stay words.
/// « dix heures trente » is « 10 h 30 », « vingt-cinq euros » « 25 € », « vingt pour cent » « 20 % », « trois virgule
/// cinq » « 3,5 ». « les deux » stays « les deux ».
public enum DictationNumbers {
    static let values: [String: Int] = [
        "zéro": 0, "zero": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8,
        "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16, "vingt": 20,
        "vingts": 20, "trente": 30, "quarante": 40, "cinquante": 50, "soixante": 60, "cent": 100, "cents": 100, "mille": 1000,
        "million": 1_000_000, "millions": 1_000_000, "milliard": 1_000_000_000, "milliards": 1_000_000_000,
    ]

    /// After a number, these make it digits even under ten.
    static let units: Set<String> = [
        "heure", "heures", "minute", "minutes", "seconde", "secondes", "euro", "euros", "€", "%", "jour", "jours", "semaine",
        "semaines", "mois", "an", "ans", "année", "années", "kilo", "kilos", "kilomètre", "kilomètres", "km", "mètre", "mètres",
    ]

    /// Before a number, these make it digits: « 14 heures cinq », « 25 euros cinquante », « 3 virgule cinq ».
    static let leads: Set<String> = ["heure", "heures", "euro", "euros", "virgule"]

    public static func digits(_ text: String) -> String {
        var tokens = Token.split(text)
        var index = 0
        while index < tokens.count {
            guard tokens[index].isWord, let run = Run.read(tokens, from: index) else {
                index += 1
                continue
            }
            let next = word(after: run.end - 1, in: tokens)
            let afterNext = next.flatMap { word(after: $0, in: tokens) }
            let nextText = next.map { tokens[$0].lower }
            let percent = nextText == "pour" && afterNext.map { ["cent", "cents"].contains(tokens[$0].lower) } == true
            let decimal = nextText == "virgule" && afterNext.map { isNumber(tokens[$0].lower) } == true
            let previous = word(before: index, in: tokens)
            let lead = previous.map { leads.contains(tokens[$0].lower) } == true
                && previous.flatMap { word(before: $0, in: tokens) }.map { tokens[$0].text.allSatisfy(\.isNumber) } == true
            let unit = nextText.map(units.contains) == true
            guard !run.isOne, run.value >= 10 || unit || percent || decimal || lead else {
                index = run.end
                continue
            }
            if percent, let afterNext {
                tokens.replaceSubrange(run.end...afterNext, with: [Token(text: " ", isWord: false), Token(text: "%", isWord: true)])
            }
            tokens.replaceSubrange(index..<run.end, with: [Token(text: String(run.value), isWord: true)])
            index += 1
        }
        return format(tokens.map(\.text).joined())
    }

    /// The units laid out once the numbers are digits.
    static func format(_ text: String) -> String {
        var text = text
        text = replace(#"(?i)(\d+) heures? et demie\b"#, in: text) { "\($0[1]) h 30" }
        text = replace(#"(?i)(\d+) heures? et quart\b"#, in: text) { "\($0[1]) h 15" }
        text = replace(#"(?i)(\d+) heures? moins le quart\b"#, in: text) { groups in
            let hour = Int(groups[1]) ?? 1
            return "\(hour == 0 ? 23 : hour - 1) h 45"
        }
        text = replace(#"(?i)(\d+) heures? (\d{1,2})\b(?! ?(?:h\b|heures?|minutes?|euros?|€|%|,\d))"#, in: text) { groups in
            guard let minutes = Int(groups[2]), minutes < 60 else { return groups[0] }
            return "\(groups[1]) h " + (minutes < 10 ? "0\(minutes)" : "\(minutes)")
        }
        text = replace(#"(?i)(\d+) heures?\b"#, in: text) { "\($0[1]) h" }
        // Whisper's own « 10h30 », « 9h » (measured 20/11).
        text = replace(#"\b(\d{1,2})h(\d{2})?\b"#, in: text) { "\($0[1]) h" + ($0[2].isEmpty ? "" : " \($0[2])") }
        text = replace(#"(?i)(\d+) euros? (\d{1,2})\b(?! ?(?:€|euros?|%|h\b))"#, in: text) { groups in
            "\(groups[1]),\(groups[2].count == 1 ? "0" + groups[2] : groups[2]) €"
        }
        text = replace(#"(?i)(\d+) euros?\b"#, in: text) { "\($0[1]) €" }
        text = replace(#"(?i)(\d+) virgule (\d+)"#, in: text) { "\($0[1]),\($0[2])" }
        return text
    }

    static func replace(_ pattern: String, in text: String, with make: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { index in
                match.range(at: index).location == NSNotFound ? "" : source.substring(with: match.range(at: index))
            }
            result += make(groups)
            last = match.range.location + match.range.length
        }
        return result + source.substring(from: last)
    }

    static func isNumber(_ word: String) -> Bool {
        word.allSatisfy(\.isNumber) || parts(word) != nil
    }

    /// A number word, or one written with hyphens (« vingt-cinq », « quatre-vingt-dix-neuf »), as its parts.
    static func parts(_ word: String) -> [String]? {
        if values[word] != nil { return [word] }
        let parts = word.split(separator: "-").map(String.init).filter { $0 != "et" }
        guard parts.count > 1, parts.allSatisfy({ values[$0] != nil }) else { return nil }
        return parts
    }

    /// The next word when only spaces lead to it.
    static func word(after index: Int, in tokens: [Token]) -> Int? {
        guard index + 2 < tokens.count, !tokens[index + 1].isWord, tokens[index + 1].text.allSatisfy({ $0 == " " }),
              tokens[index + 2].isWord else { return nil }
        return index + 2
    }

    static func word(before index: Int, in tokens: [Token]) -> Int? {
        guard index >= 2, !tokens[index - 1].isWord, tokens[index - 1].text.allSatisfy({ $0 == " " }),
              tokens[index - 2].isWord else { return nil }
        return index - 2
    }

    struct Token: Equatable {
        var text: String
        var isWord: Bool
        var lower: String { text.lowercased() }

        static func split(_ text: String) -> [Token] {
            guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}€%]+(?:[-'’][\p{L}\p{N}]+)*"#) else { return [] }
            let source = text as NSString
            var tokens: [Token] = []
            var last = 0
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                if match.range.location > last {
                    tokens.append(Token(text: source.substring(with: NSRange(location: last, length: match.range.location - last)), isWord: false))
                }
                tokens.append(Token(text: source.substring(with: match.range), isWord: true))
                last = match.range.location + match.range.length
            }
            if last < source.length { tokens.append(Token(text: source.substring(from: last), isWord: false)) }
            return tokens
        }
    }

    /// The number words that follow each other and make one number: « deux mille vingt-six », « soixante et onze ».
    struct Run {
        var value: Int
        /// The token after the last word of the number.
        var end: Int
        var isOne: Bool

        static func read(_ tokens: [Token], from start: Int) -> Run? {
            var number = Number()
            var index = start
            var end = start
            while index < tokens.count, tokens[index].isWord {
                let word = tokens[index].lower
                if word == "et" {
                    // « vingt et un », « soixante et onze »: only between a ten and what follows it.
                    guard number.started, [20, 30, 40, 50, 60].contains(number.lastPart), let next = DictationNumbers.word(after: index, in: tokens),
                          ["un", "une", "onze"].contains(tokens[next].lower) else { break }
                    index = next
                    continue
                }
                guard let parts = DictationNumbers.parts(word) else { break }
                var tried = number
                guard parts.allSatisfy({ tried.add(values[$0] ?? 0) }) else { break }
                number = tried
                end = index + 1
                guard let next = DictationNumbers.word(after: index, in: tokens) else { break }
                index = next
            }
            guard number.started else { return nil }
            // « un », « une » stay words; « mille » alone too: « mille mercis ».
            return Run(value: number.value, end: end, isOne: end == start + 1 && ["un", "une", "mille"].contains(tokens[start].lower))
        }
    }

    /// A French number said word after word, with what may come next.
    struct Number {
        var total = 0
        var current = 0
        var started = false
        /// The value of the last word added.
        var lastPart = -1
        /// What may still be added: below this.
        var limit = Int.max
        var thousands = false

        var value: Int { total + current }

        mutating func add(_ part: Int) -> Bool {
            switch part {
            case 100:
                guard current < 10, lastPart != 100, lastPart != 0 else { return false }
                current = max(current, 1) * 100
                limit = 100
            case 1000:
                guard !thousands, current < 1000, lastPart != 0 else { return false }
                total += max(current, 1) * 1000
                current = 0
                limit = 1000
                thousands = true
            case 1_000_000...:
                guard current < 1000, total < part, lastPart != 0 else { return false }
                total += max(current, 1) * part
                current = 0
                limit = part
            case 20 where lastPart == 4 && current % 100 == 4:
                // « quatre-vingt »: four twenties.
                current += 76
                limit = 20
                lastPart = 80
                started = true
                return true
            default:
                guard part < limit, !(lastPart == 10 && !(7...9).contains(part)) else { return false }
                if part == 0, started { return false }
                current += part
                switch part {
                case 0, 1...9, 11...19: limit = 0
                case 10: limit = 10
                case 60: limit = 20
                default: limit = 10
                }
            }
            lastPart = part
            started = true
            return true
        }
    }
}
