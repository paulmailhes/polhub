import Foundation
import Persistence

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

    public func write(_ data: Data, to url: URL, quarantine: Bool = false) throws {
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
