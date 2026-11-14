import CoreServices
import Foundation
import Persistence
import MailFormat

/// A message read whole from Gmail: its row, its body, and the small images its HTML carries.
public struct ParsedMail: Sendable {
    public var row: MailMessageRow
    /// The HTML as the sender wrote it, never rewritten; or the text of a mail without HTML.
    public var body: String?
    /// Images Gmail gave with the message itself, by part.
    public var inline: [String: Data]
}

/// Turns Gmail's answer (`format=full`) into what the app keeps (14/11).
public enum MailParser {
    public static func parse(_ message: GmailAPI.Message, account: String) -> ParsedMail {
        let payload = message.payload
        let parts = payload?.all ?? []
        let htmlIndex = parts.firstIndex { $0.mimeType == "text/html" && ($0.filename ?? "").isEmpty }
        let plainIndex = parts.firstIndex { $0.mimeType == "text/plain" && ($0.filename ?? "").isEmpty }
        let html = htmlIndex.map { parts[$0] }
        let chosenIndex = htmlIndex ?? plainIndex
        let chosen = chosenIndex.map { parts[$0] }
        let body = chosen.flatMap { part in part.body?.bytes.map { text($0, declared: MailProbe.charset(of: part)) } }
        let lowerHTML = html != nil ? body?.lowercased() : nil
        var attachments: [MailAttachment] = []
        var inline: [String: Data] = [:]
        for (index, part) in parts.enumerated() {
            let name = part.filename ?? ""
            let contentID = part.header("Content-ID")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            guard !name.isEmpty || contentID != nil, part.mimeType?.hasPrefix("multipart/") != true, index != chosenIndex else { continue }
            let partID = part.partId ?? String(index)
            // Shown by the HTML itself: an image it names by `cid:`.
            let shown = contentID.map { lowerHTML?.contains("cid:\($0.lowercased())") == true } ?? false
            attachments.append(MailAttachment(partID: partID, filename: AttachmentSafety.cleanName(name.isEmpty ? "image" : name),
                                              mimeType: part.mimeType ?? "application/octet-stream", size: part.body?.size ?? 0,
                                              attachmentID: part.body?.attachmentId, contentID: contentID, inline: shown))
            if shown, let bytes = part.body?.bytes { inline[partID] = bytes }
        }
        let authentication = payload?.header("Authentication-Results")?.lowercased() ?? ""
        let date = message.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1_000) } ?? Date(timeIntervalSince1970: 0)
        let subject = decodedWords(payload?.header("Subject") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let row = MailMessageRow(
            account: account, messageID: message.id, threadID: message.threadId ?? message.id, date: date,
            sender: addresses(payload?.header("From")).first, to: addresses(payload?.header("To")), cc: addresses(payload?.header("Cc")),
            subject: subject.isEmpty ? "(sans objet)" : subject, snippet: entities(message.snippet ?? ""), labels: message.labelIds ?? [],
            rfcMessageID: payload?.header("Message-ID"), authenticated: authentication.contains("dmarc=pass"),
            listUnsubscribe: payload?.header("List-Unsubscribe"), listUnsubscribePost: payload?.header("List-Unsubscribe-Post"),
            hasBody: body != nil, bodyIsHTML: html != nil && body != nil, attachments: attachments
        )
        return ParsedMail(row: row, body: body, inline: inline)
    }

    /// The text of a part. Gmail hands the bytes over in UTF-8 even when the mail declares another set (measured
    /// on 14/11: 75 mails of 900 showed « accÃ¨s » for « accès »): valid UTF-8 wins, then the declared set, then
    /// Windows' Latin set, which accepts any byte.
    public static func text(_ bytes: Data, declared charset: String) -> String {
        if let utf8 = String(data: bytes, encoding: .utf8) { return utf8 }
        if let declared = MailProbe.text(bytes, charset: charset) { return declared }
        return String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
    }

    /// A body kept before 14/11 and read in the wrong set: the UTF-8 it really was. `nil` when it is fine.
    public static func repaired(_ text: String) -> String? {
        let markers = ["Ã©", "Ã¨", "Ã ", "Ã\u{a0}", "Ã§", "Ãª", "Ã‰", "Ã´", "Ã®", "Ã¹", "Ã»", "Ã¢", "Ã«", "Ã¯", "â€™", "â€œ", "â€\u{9d}", "â€“", "â€¦"]
        guard markers.contains(where: text.contains) else { return nil }
        for encoding in [String.Encoding.isoLatin1, .windowsCP1252] {
            if let bytes = text.data(using: encoding), let fixed = String(data: bytes, encoding: .utf8), fixed != text { return fixed }
        }
        return nil
    }

    /// `Camille Martin <camille@exemple.fr>, "Durand, Jules" <jules@exemple.fr>, seul@exemple.fr`.
    static func addresses(_ header: String?) -> [MailAddress] {
        guard let header, !header.isEmpty else { return [] }
        var pieces: [String] = [], current = "", quoted = false, angled = false
        for character in header {
            switch character {
            case "\"": quoted.toggle(); current.append(character)
            case "<" where !quoted: angled = true; current.append(character)
            case ">" where !quoted: angled = false; current.append(character)
            case "," where !quoted && !angled: pieces.append(current); current = ""
            default: current.append(character)
            }
        }
        pieces.append(current)
        return pieces.compactMap { piece in
            let text = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
                let email = String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
                let name = decodedWords(String(text[..<open])).trimmingCharacters(in: CharacterSet(charactersIn: "\" \t"))
                return email.contains("@") ? MailAddress(name: name, email: email) : nil
            }
            return text.contains("@") ? MailAddress(email: text) : nil
        }
    }

    /// RFC 2047: `=?UTF-8?Q?R=C3=A9union?=` and `=?UTF-8?B?…?=` in a header, when Gmail gives them as they came.
    static func decodedWords(_ text: String) -> String {
        guard text.contains("=?"), let pattern = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#) else { return text }
        var result = text
        // Two encoded words in a row are one text: the blank between them is not part of it.
        result = result.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result), let charset = Range(match.range(at: 1), in: result),
                  let kind = Range(match.range(at: 2), in: result), let payload = Range(match.range(at: 3), in: result) else { continue }
            let bytes: Data?
            if result[kind].lowercased() == "b" {
                bytes = Data(base64Encoded: String(result[payload]))
            } else {
                var data = Data(), characters = Array(result[payload].replacingOccurrences(of: "_", with: " ").utf8), index = 0
                while index < characters.count {
                    if characters[index] == UInt8(ascii: "="), index + 2 < characters.count,
                       let byte = UInt8(String(decoding: characters[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                        data.append(byte)
                        index += 3
                    } else {
                        data.append(characters[index])
                        index += 1
                    }
                }
                bytes = data
            }
            if let bytes { result.replaceSubrange(whole, with: MailParser.text(bytes, declared: result[charset].lowercased())) }
        }
        return result
    }

    /// Gmail's extract comes with a few HTML entities.
    static func entities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
