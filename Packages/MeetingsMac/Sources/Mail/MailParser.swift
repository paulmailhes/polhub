import CoreServices
import Foundation
import Persistence

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

/// What a received file may be called and whether Polhub may open it itself.
public enum AttachmentSafety {
    /// A name safe to write on disk: no folder, no hidden file, no control character.
    public static func cleanName(_ name: String) -> String {
        let last = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let safe = String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" })
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return safe.isEmpty ? "piece-jointe" : String(safe.prefix(120))
    }

    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case badName(String)
        case folder(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .badName(let name): "« \(name) » n'est pas un nom de pièce jointe permis"
            case .folder(let name): "« \(name) » est un dossier : compresse-le d'abord"
            case .unreadable(let name): "« \(name) » ne peut pas être lu"
            }
        }
    }

    /// A name not yet among `taken`: « devis.pdf », then « devis 2.pdf ».
    public static func uniqueName(_ name: String, taken: Set<String>) -> String {
        let clean = cleanName(name)
        guard taken.contains(clean) else { return clean }
        let base = (clean as NSString).deletingPathExtension, ext = (clean as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !taken.contains(candidate) { return candidate }
            index += 1
        }
    }

    /// A file Paul joins: the file a link points to, never a folder or a bundle (`.pages`, `.app`), with its size.
    public static func joinable(_ url: URL) throws -> (url: URL, size: Int) {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isRegularFileKey, .fileSizeKey])
        if values?.isDirectory == true || values?.isPackage == true { throw Refusal.folder(url.lastPathComponent) }
        guard values?.isRegularFile == true, let size = values?.fileSize else { throw Refusal.unreadable(url.lastPathComponent) }
        return (resolved, size)
    }

    static let previewable: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "pdf", "txt", "md", "csv", "rtf", "mp3", "m4a",
                                           "wav", "mp4", "mov", "docx", "xlsx", "pptx", "doc", "xls", "ppt", "pages", "numbers", "key"]

    /// Decided on the cleaned name's extension, never on the type the sender declares: an image, a PDF, a
    /// document. Anything else (HTML, archive, program) is only saved.
    public static func canOpen(name: String) -> Bool {
        previewable.contains((cleanName(name) as NSString).pathExtension.lowercased())
    }
}

/// Where the bodies and the files of the mails live: beside the base, one folder per mailbox.
public struct MailFiles: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.appending(path: "Mails", directoryHint: .isDirectory)
    }

    public func folder(account: String) -> URL {
        root.appending(path: account.lowercased(), directoryHint: .isDirectory)
    }

    public func body(of message: MailMessageRow) -> URL {
        folder(account: message.account).appending(path: "\(message.messageID).\(message.bodyIsHTML ? "html" : "txt")")
    }

    /// The files Paul joined to a draft, kept beside it until it leaves (whatever the mailbox it leaves from).
    public func draftFolder(_ draft: MailDraftRow) -> URL {
        draftFolder(id: draft.id)
    }

    /// One folder per draft, named by its id: an id that is not a UUID (a row written by hand) gets a name
    /// that cannot leave `brouillons` (review of 14/11).
    public func draftFolder(id: String) -> URL {
        let name = UUID(uuidString: id).map { $0.uuidString.lowercased() } ?? "invalide-" + String(id.filter { $0.isLetter || $0.isNumber }.prefix(40))
        return root.appending(path: "brouillons", directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
    }

    /// A draft's file, only if its name is one Polhub would have written and it stays in the draft's folder.
    public func draftFile(_ file: MailDraftFile, of draft: MailDraftRow) throws -> URL {
        let folder = draftFolder(draft)
        guard file.filename == AttachmentSafety.cleanName(file.filename) else { throw AttachmentSafety.Refusal.badName(file.filename) }
        let url = folder.appending(path: file.filename)
        guard url.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false) == folder.standardizedFileURL.path(percentEncoded: false)
        else { throw AttachmentSafety.Refusal.badName(file.filename) }
        return url
    }

    public func attachment(_ attachment: MailAttachment, of message: MailMessageRow) -> URL {
        folder(account: message.account).appending(path: "\(message.messageID)-\(attachment.partID)", directoryHint: .isDirectory)
            .appending(path: AttachmentSafety.cleanName(attachment.filename))
    }

    func write(_ data: Data, to url: URL, quarantine: Bool = false) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        guard quarantine else { return }
        // macOS treats the file as coming from a mail: it warns before opening what could run.
        var values = URLResourceValues()
        values.quarantineProperties = [kLSQuarantineTypeKey as String: kLSQuarantineTypeEmailAttachment as String,
                                       kLSQuarantineAgentNameKey as String: "Polhub"]
        var target = url
        try? target.setResourceValues(values)
    }

    /// The mailboxes whose account is gone lose their folder, and the drafts that are gone theirs.
    public func keepOnly(accounts: [String], drafts: [String]) {
        let kept = Set(accounts.map { $0.lowercased() } + ["brouillons"])
        for folder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where !kept.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
        let draftsKept = Set(drafts)
        let draftsRoot = root.appending(path: "brouillons", directoryHint: .isDirectory)
        for folder in (try? FileManager.default.contentsOfDirectory(at: draftsRoot, includingPropertiesForKeys: nil)) ?? []
        where !draftsKept.contains(folder.lastPathComponent) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
