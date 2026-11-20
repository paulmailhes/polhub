import Foundation
import Persistence

/// What a received file may be called and whether Polhub may open it itself.
public enum AttachmentSafety {
    /// A name safe to write on disk: no folder, no hidden file, no control character. 120 characters at most, the
    /// extension kept; a name cleaned once stays as it is (review of 16/11: the app takes up an agent's file only under
    /// a name Polhub would write).
    public static func cleanName(_ name: String) -> String {
        let last = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let safe = trimmed(String(last.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != ":" }))
        guard !safe.isEmpty else { return "piece-jointe" }
        return safe.count > longestName ? fitted(safe, suffix: "") : safe
    }

    static let longestName = 120

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
    }

    /// A clean name with `suffix` before its extension (« devis 2.pdf »), in 120 characters: the stem gives way, then is
    /// trimmed again. An extension too long to be one goes with the rest.
    static func fitted(_ name: String, suffix: String) -> String {
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        let keepsExtension = !ext.isEmpty && ext.count <= 10 && !stem.isEmpty
        let tail = suffix + (keepsExtension ? "." + ext : "")
        let cut = trimmed(String((keepsExtension ? stem : name).prefix(longestName - tail.count)))
        return (cut.isEmpty ? "piece-jointe" : cut) + tail
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
        var index = 2
        while true {
            // Still 120 characters at most: the stem gives way to the number (review of 16/11).
            let candidate = fitted(clean, suffix: " \(index)")
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

/// A refusal in Paul's words, for `Words.problem` (lot 10, 20/11): the reason without the name, which the sentence says
/// before it (« « Photos » n'a pas pu être joint : c'est un dossier. »), and what to do. `description` does not move.
extension AttachmentSafety.Refusal: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .badName: "ce nom n'est pas permis pour une pièce jointe"
        case .folder: "c'est un dossier"
        case .unreadable: "le fichier ne se lit pas"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .badName: "Renomme le fichier, puis joins-le."
        case .folder: "Compresse-le, puis joins le fichier compressé."
        case .unreadable: nil
        }
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

    /// Everything the Mac holds of these messages of a mailbox: their body (HTML or text) and every file of theirs,
    /// shown or downloaded, removed (a mail gone to the spam keeps only its headers, wave B).
    public func forget(messageIDs: Set<String>, account: String) {
        guard !messageIDs.isEmpty else { return }
        let folder = folder(account: account)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [] {
            let id = name.hasSuffix(".html") || name.hasSuffix(".txt") ? (name as NSString).deletingPathExtension
                : name.range(of: "-", options: .backwards).map { String(name[..<$0.lowerBound]) } ?? ""
            if messageIDs.contains(id) { try? FileManager.default.removeItem(at: folder.appending(path: name)) }
        }
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

    /// The mailboxes whose account is gone lose their folder, and the drafts that are gone theirs. The agents' files
    /// waiting for the app stay: their drop may be written in this very moment.
    public func keepOnly(accounts: [String], drafts: [String]) {
        let kept = Set(accounts.map { $0.lowercased() } + ["brouillons", Self.requestsName, Self.agentsName])
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

// MARK: - The agents' requests for a file (16/11)

/// An attachment an agent asked for (`polhub mcp`, which has no network): the app downloads it, then removes the
/// request. Paul, 16/11: « Polhub ne sait pas lire les fichiers joints ».
public struct MailFileRequest: Codable, Equatable, Sendable {
    public var account: String
    public var messageID: String
    public var partID: String

    public init(account: String, messageID: String, partID: String) {
        self.account = account
        self.messageID = messageID
        self.partID = partID
    }
}

extension MailFiles {
    /// The signal the helper posts after a request: the app serves it at once.
    public static let requestSignal = "fr.paulmailhes.polhub.piece-demandee"
    static let requestsName = "demandes"

    var requestsFolder: URL { root.appending(path: Self.requestsName, directoryHint: .isDirectory) }

    /// Leaves a request for the app.
    public func request(_ request: MailFileRequest) throws {
        try FileManager.default.createDirectory(at: requestsFolder, withIntermediateDirectories: true)
        try JSONEncoder().encode(request).write(to: requestsFolder.appending(path: "\(UUID().uuidString).json"), options: .atomic)
    }

    /// The requests waiting, the oldest first; an unreadable one is dropped.
    public func pendingRequests() -> [(file: URL, request: MailFileRequest)] {
        let names = (try? FileManager.default.contentsOfDirectory(at: requestsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return names.filter { $0.pathExtension == "json" }
            .sorted { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast) ?? .distantPast
                < (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast) ?? .distantPast }
            .compactMap { file in
                guard let data = try? Data(contentsOf: file), let request = try? JSONDecoder().decode(MailFileRequest.self, from: data) else {
                    try? FileManager.default.removeItem(at: file)
                    return nil
                }
                return (file, request)
            }
    }

    /// A request served (or that cannot be).
    public func served(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }
}

// MARK: - The files an agent joins (16/11)

extension MailFiles {
    static let agentsName = "agents"

    var agentsFolder: URL { root.appending(path: Self.agentsName, directoryHint: .isDirectory) }

    /// The files an agent joined to a drop, copied by `polhub mcp` until the app makes the drop a draft: one folder per
    /// drop, named by its id, as the drafts' (an id that is not a UUID cannot leave `agents`).
    public func agentFolder(id: String) -> URL {
        let name = UUID(uuidString: id).map { $0.uuidString.lowercased() } ?? "invalide-" + String(id.filter { $0.isLetter || $0.isNumber }.prefix(40))
        return agentsFolder.appending(path: name, directoryHint: .isDirectory)
    }

    /// A file of a drop, only if its name is one Polhub would have written and it stays in the drop's folder: a row
    /// written by hand never reaches another file of the Mac.
    public func agentFile(_ file: MailDraftFile, of drop: MailAgentDraftRow) throws -> URL {
        let folder = agentFolder(id: drop.id)
        guard file.filename == AttachmentSafety.cleanName(file.filename) else { throw AttachmentSafety.Refusal.badName(file.filename) }
        let url = folder.appending(path: file.filename)
        guard url.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false) == folder.standardizedFileURL.path(percentEncoded: false)
        else { throw AttachmentSafety.Refusal.badName(file.filename) }
        return url
    }

    /// The folders of drops gone (adopted or let go) for some time: what a helper stopped on the way left behind.
    public func forgetAgentFolders(keeping drops: Set<String>, olderThan age: TimeInterval = 3_600, now: Date = Date()) {
        let kept = Set(drops.map { agentFolder(id: $0).lastPathComponent })
        for folder in (try? FileManager.default.contentsOfDirectory(at: agentsFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        where !kept.contains(folder.lastPathComponent) {
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if now.timeIntervalSince(created) > age { try? FileManager.default.removeItem(at: folder) }
        }
    }
}
