import Foundation

/// A mail in plain text, cut in three for the page (Paul, 19/11): what was written, the signature, the quoted history.
/// The page folds the last two behind a button each; nothing is ever removed. The rules are those of the HTML page
/// (`MailHTML.readerScript`), measured on real threads in French, English and German: an attribution line (« Le … à
/// 17:28, … a écrit : », « On … wrote: »), Outlook's header block (De / Envoyé or Date / À / Objet, From / Sent / To /
/// Subject, Von / Gesendet / An / Betreff), « -----Message d'origine----- », a trailing run of « > » lines; a
/// signature after « -- », or after a closing and a first name when what follows looks like one (a phone, an address,
/// a site, a legal notice), and the mobile footers. A forward is no history: it stays. What would leave nothing written
/// folds nothing.
public enum MailPlainText {
    public struct Parts: Equatable, Sendable {
        public var text: String
        public var signature: String?
        public var quote: String?

        public init(text: String, signature: String?, quote: String?) {
            self.text = text
            self.signature = signature
            self.quote = quote
        }
    }

    public static func parts(_ body: String) -> Parts {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let plain = lines.map(normalized)
        var ownEnd = lines.count
        var quote: String?
        if let start = quoteStart(plain), hasWords(plain[..<start]) {
            ownEnd = start
            quote = joined(lines[start...])
        }
        var signatureLine: Int?
        let own = Array(plain[..<ownEnd])
        if let start = signatureStart(own), hasWords(own[..<start]) { signatureLine = start }
        let textEnd = signatureLine ?? ownEnd
        let signature = signatureLine.map { joined(lines[$0..<ownEnd]) }
        return Parts(text: joined(lines[..<textEnd]), signature: signature.flatMap { $0.isEmpty ? nil : $0 }, quote: quote)
    }

    // MARK: - The history

    static let attributions = [
        #"^Le\s.{4,250}?(\d{1,2}[:h]\d{2}|\d{4}).{0,250}?\sa\s+écrit\s*:$"#,
        #"^On\s.{4,300}?(\d{1,2}:\d{2}|\d{4}).{0,300}?\bwrote\s*:$"#,
        #"^Am\s.{4,250}?(\d{1,2}:\d{2}|\d{4}).{0,250}?\sschrieb\b.{0,200}:$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    static let original = #"^-{2,}\s*(Message d'origine|Message original|Mail original|Courriel original|Original Message|Ursprüngliche Nachricht)\s*-{2,}$"#
    static let forward = #"^(-{2,}\s*(Forwarded message|Message transféré|Mail transféré|Message transmis|Weitergeleitete Nachricht)\s*-{2,}|(Début du message (réexpédié|transféré)|Begin forwarded message)\s*:)"#
    static let from = #"^\*?(De|From|Von|Expéditeur)\s*\*?\s*:"#
    static let when = #"^\*?(Envoyé( le| par)?|Sent|Date|Gesendet|Datum)\s*\*?\s*:.*\d"#
    static let other = #"^\*?(À|A|To|An|Cc|Cci|Bcc|Objet|Subject|Betreff|Sujet|Répondre à|Reply-To)\s*\*?\s*:"#

    /// Where the quoted history starts: the first line that opens one, in the lines as Outlook and Gmail write them.
    static func quoteStart(_ lines: [String]) -> Int? {
        for index in lines.indices {
            let line = unquoted(lines[index])
            if matches(line, forward) { return nil }
            // An attribution, possibly wrapped on up to three lines.
            for span in 1...3 where index + span <= lines.count {
                let joinedLine = lines[index..<(index + span)].map(unquoted).joined(separator: " ")
                if attributions.contains(where: { $0.firstMatch(in: joinedLine, range: NSRange(joinedLine.startIndex..., in: joinedLine)) != nil }) {
                    return index
                }
            }
            if matches(line, original) { return index }
            if isHeaderBlock(lines, at: index) { return index }
            // A line of underscores just above a header block (Outlook for iOS, Outlook on the web).
            if line.range(of: #"^_{20,}$"#, options: .regularExpression) != nil,
               (index + 1...min(index + 2, lines.count - 1)).contains(where: { isHeaderBlock(lines, at: $0) }) {
                return index
            }
            // A trailing run of at least three « > » lines, with nothing written after it.
            if lines[index].hasPrefix(">") {
                let rest = lines[index...]
                if rest.allSatisfy({ $0.hasPrefix(">") || $0.isEmpty }), rest.filter({ $0.hasPrefix(">") }).count >= 3 { return index }
            }
        }
        return nil
    }

    /// A « De : » line followed, within five lines, by a date line and another header.
    static func isHeaderBlock(_ lines: [String], at index: Int) -> Bool {
        guard index < lines.count, matches(unquoted(lines[index]), from) else { return false }
        let next = lines[(index + 1)..<min(index + 6, lines.count)].map(unquoted)
        return next.contains { matches($0, when) } && next.contains { matches($0, other) }
    }

    // MARK: - The signature

    static let closing = #"^(cordialement|bien cordialement|très cordialement|bien à (vous|toi)|bonne (journée|soirée|fin de journée|semaine)|belle journée|à (bientôt|très vite|demain)|amicalement|amitiés|bises|merci( beaucoup| encore| d'avance)?|(sincères |meilleures )?salutations|best( regards| wishes)?|kind regards|warm regards|regards|many thanks.{0,30}|thanks.{0,20}|cheers|herzliche grüße|mit freundlichen grüßen|beste grüße|viele grüße)[\s,.!]*$"#
    static let mobile = #"^(Envoyé de mon (iPhone|iPad)|Envoyé depuis .{1,40}|Envoyé à partir de Outlook pour (iOS|Android)|Sent from my \w+.{0,20}|Sent from Outlook for (iOS|Android)|Get Outlook for (iOS|Android)|Obtenir Outlook pour (iOS|Android))"#
    /// What a signature holds: a phone, an address, a site, a mail, a legal notice.
    static let evidence = [
        #"(\+\d{2,3}|\b0)\s?\(?\d\)?([\s.\-]?\d{2}){4}"#, #"[\w.+-]+@[\w-]+\.\w"#, #"(www\.|https?://|\.(fr|com|net|org|io|eu|de|co)\b)"#,
        #"\b\d{1,4},?\s+(bis\s+|ter\s+)?(rue|avenue|av\.|boulevard|bd|place|allée|quai|chemin|impasse|cours)\b"#, #"\b\d{5}\s+\p{L}"#,
        #"(confidenti|destinataire|intended solely|privileged|Datenschutz|n'imprimez|the environment|l'environnement)"#,
    ]

    /// Where the signature starts in what was written: a « -- » line near the end, a mobile footer as the last line,
    /// or the block after a closing and a first name.
    static func signatureStart(_ lines: [String]) -> Int? {
        let filled = lines.indices.filter { !lines[$0].isEmpty }
        guard let last = filled.last else { return nil }
        if let dash = lines.indices.last(where: { lines[$0] == "--" }), filled.filter({ $0 > dash }).count <= 15 { return dash }
        if matches(lines[last], mobile), filled.count > 1 {
            // A footer under a signature: the signature's start, if there is one, else the footer alone.
            return signatureAfterClosing(Array(lines[..<last])) ?? last
        }
        return signatureAfterClosing(lines)
    }

    static func signatureAfterClosing(_ lines: [String]) -> Int? {
        guard let closingLine = lines.indices.last(where: { lines[$0].count <= 60 && matches(lines[$0], closing) }),
              let name = lines.indices.first(where: { $0 > closingLine && !lines[$0].isEmpty }), lines[name].count <= 40 else { return nil }
        let tail = lines[(name + 1)...].filter { !$0.isEmpty }
        let text = tail.joined(separator: "\n")
        let proofs = evidence.filter { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }.count
        guard tail.count >= 2, proofs >= 1 else { return nil }
        // Every line of it looks like one: a long sentence in the middle is something written, not a signature.
        guard tail.allSatisfy({ $0.count <= 160 || matches($0, evidence[5]) }) else { return nil }
        return lines.indices.first { $0 > name && !lines[$0].isEmpty }
    }

    // MARK: - Helpers

    /// No-break and thin spaces made plain, the line trimmed.
    static func normalized(_ line: String) -> String {
        line.replacingOccurrences(of: "[\u{00A0}\u{202F}\u{2009}\u{200B}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// A line without its « > » marks.
    static func unquoted(_ line: String) -> String {
        line.replacingOccurrences(of: #"^(>\s?)+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    static func matches(_ line: String, _ pattern: String) -> Bool {
        line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func hasWords(_ lines: ArraySlice<String>) -> Bool {
        lines.contains { !$0.isEmpty && !matches($0, mobile) }
    }

    /// Lines put back together, the blank ones at either end left out.
    static func joined(_ lines: ArraySlice<String>) -> String {
        var slice = lines
        while let first = slice.first, first.trimmingCharacters(in: .whitespaces).isEmpty { slice = slice.dropFirst() }
        while let last = slice.last, last.trimmingCharacters(in: .whitespaces).isEmpty { slice = slice.dropLast() }
        return slice.joined(separator: "\n")
    }
}
