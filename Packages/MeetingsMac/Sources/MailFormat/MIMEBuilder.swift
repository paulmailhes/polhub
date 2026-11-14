import Foundation
import Persistence

/// A mail ready to leave: who, what, the thread it answers, its files.
public struct OutgoingMail: Sendable, Equatable {
    public var from: MailAddress
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var bcc: [MailAddress]
    public var subject: String
    public var text: String
    public var html: String
    public var inReplyTo: String?
    public var references: String?
    public var files: [OutgoingFile]
    public var date: Date

    public init(from: MailAddress, to: [MailAddress], cc: [MailAddress] = [], bcc: [MailAddress] = [], subject: String, text: String, html: String,
                inReplyTo: String? = nil, references: String? = nil, files: [OutgoingFile] = [], date: Date) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.text = text
        self.html = html
        self.inReplyTo = inReplyTo
        self.references = references
        self.files = files
        self.date = date
    }
}

public struct OutgoingFile: Sendable, Equatable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

/// The message as it travels (RFC 5322 and MIME), built by hand: Gmail sends what it is given (14/11).
/// Text and HTML in quoted-printable UTF-8, files in base64, headers encoded when they are not plain ASCII,
/// CR and LF never let through a header.
public enum MIMEBuilder {
    /// Gmail's limit for the files of one mail.
    public static let maximumFiles = 25 * 1_000_000

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case noRecipient
        case badAddress(String)
        case tooLarge

        public var description: String {
            switch self {
            case .noRecipient: "le mail n'a aucun destinataire"
            case .badAddress(let address): "l'adresse « \(address) » n'est pas valide"
            case .tooLarge: "les pièces jointes dépassent 25 Mo, la limite de Gmail"
            }
        }
    }

    /// An address Gmail will take: one `@`, a dot after it, nothing that could break a header.
    public static func isValid(_ email: String) -> Bool {
        email.range(of: #"^[^\s@<>(),;:\\"\[\]]+@[^\s@<>(),;:\\"\[\]]+\.[^\s@<>(),;:\\"\[\].]+$"#, options: .regularExpression) != nil
    }

    /// The message to send; a `draft` may have no recipient yet, and keeps only the valid addresses typed so far.
    public static func build(_ input: OutgoingMail, draft: Bool = false, boundary: () -> String = { "polhub-\(UUID().uuidString)" }) throws -> Data {
        var mail = input
        if draft {
            mail.to = mail.to.filter { isValid($0.email) }
            mail.cc = mail.cc.filter { isValid($0.email) }
            mail.bcc = mail.bcc.filter { isValid($0.email) }
        } else {
            let all = mail.to + mail.cc + mail.bcc
            guard !all.isEmpty else { throw Failure.noRecipient }
            if let bad = all.first(where: { !isValid($0.email) }) { throw Failure.badAddress(bad.email) }
        }
        guard isValid(mail.from.email) else { throw Failure.badAddress(mail.from.email) }
        guard mail.files.reduce(0, { $0 + $1.data.count }) <= maximumFiles else { throw Failure.tooLarge }

        var lines: [String] = [
            header("From", address(mail.from)),
        ]
        if !mail.to.isEmpty { lines.append(header("To", mail.to.map(address).joined(separator: ", "))) }
        if !mail.cc.isEmpty { lines.append(header("Cc", mail.cc.map(address).joined(separator: ", "))) }
        // Gmail sends to the Bcc and takes the header out of what the others receive.
        if !mail.bcc.isEmpty { lines.append(header("Bcc", mail.bcc.map(address).joined(separator: ", "))) }
        lines.append(header("Subject", encodedText(mail.subject)))
        lines.append(header("Date", rfcDate(mail.date)))
        if let inReplyTo = mail.inReplyTo.map(clean), !inReplyTo.isEmpty { lines.append(header("In-Reply-To", inReplyTo)) }
        if let references = mail.references.map(clean), !references.isEmpty { lines.append(header("References", references)) }
        lines.append("MIME-Version: 1.0")

        let alternativeBoundary = boundary()
        let alternative = [
            "Content-Type: multipart/alternative; boundary=\"\(alternativeBoundary)\"",
            "",
            "--\(alternativeBoundary)",
            "Content-Type: text/plain; charset=\"UTF-8\"",
            "Content-Transfer-Encoding: quoted-printable",
            "",
            quotedPrintable(mail.text),
            "--\(alternativeBoundary)",
            "Content-Type: text/html; charset=\"UTF-8\"",
            "Content-Transfer-Encoding: quoted-printable",
            "",
            quotedPrintable(mail.html),
            "--\(alternativeBoundary)--",
        ]
        if mail.files.isEmpty {
            lines += alternative
        } else {
            let mixedBoundary = boundary()
            lines.append("Content-Type: multipart/mixed; boundary=\"\(mixedBoundary)\"")
            lines.append("")
            lines.append("--\(mixedBoundary)")
            lines += alternative
            for file in mail.files {
                let name = clean(file.filename)
                lines.append("--\(mixedBoundary)")
                lines.append("Content-Type: \(clean(file.mimeType)); name=\"\(encodedText(name).replacingOccurrences(of: "\"", with: "'"))\"")
                lines.append("Content-Disposition: attachment; filename*=UTF-8''\(percentEncoded(name))")
                lines.append("Content-Transfer-Encoding: base64")
                lines.append("")
                lines.append(file.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]))
            }
            lines.append("--\(mixedBoundary)--")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// What Gmail's API takes in `raw`.
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Pieces

    /// No CR, no LF, no other control character: a header can never be split into two.
    static func clean(_ value: String) -> String {
        String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\t" }).replacingOccurrences(of: "\t", with: " ")
    }

    static func header(_ name: String, _ value: String) -> String {
        "\(name): \(value)"
    }

    static func isPlainASCII(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F }
    }

    /// RFC 2047, UTF-8 and base64, in words of 75 characters at most, folded on continuation lines; never cut
    /// inside a character.
    static func encodedText(_ raw: String) -> String {
        let text = clean(raw)
        guard !isPlainASCII(text) else { return text }
        var words: [String] = [], chunk = ""
        for character in text {
            if Data((chunk + String(character)).utf8).count > 45 {
                words.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { words.append(chunk) }
        return words.map { "=?UTF-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }

    /// `Name <adresse>`: a name with ASCII specials is quoted, a name beyond ASCII is encoded. A comma in a name
    /// can never add a recipient.
    static func address(_ address: MailAddress) -> String {
        let email = clean(address.email).replacingOccurrences(of: " ", with: "")
        guard let name = address.name.map(clean), !name.isEmpty else { return email }
        if !isPlainASCII(name) { return "\(encodedText(name)) <\(email)>" }
        let specials = CharacterSet(charactersIn: "()<>[]:;@\\,.\"")
        if name.unicodeScalars.contains(where: specials.contains) {
            return "\"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" <\(email)>"
        }
        return "\(name) <\(email)>"
    }

    static func rfcDate(_ date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = .current
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return format.string(from: date)
    }

    /// RFC 2231, for a file name in UTF-8.
    static func percentEncoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "piece-jointe"
    }

    /// RFC 2045: lines of 76 characters at most, `=` and bytes beyond ASCII escaped, line ends as CRLF, a space
    /// before a line end escaped.
    static func quotedPrintable(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            var encoded = "", length = 0
            let bytes = Array(line.utf8)
            for (index, byte) in bytes.enumerated() {
                let last = index == bytes.count - 1
                let piece: String
                if (byte >= 33 && byte <= 126 && byte != 61) || ((byte == 32 || byte == 9) && !last) {
                    piece = String(UnicodeScalar(byte))
                } else {
                    piece = String(format: "=%02X", byte)
                }
                if length + piece.count > 75 {
                    encoded += "=\r\n"
                    length = 0
                }
                encoded += piece
                length += piece.count
            }
            output.append(encoded)
        }
        return output.joined(separator: "\r\n")
    }
}
