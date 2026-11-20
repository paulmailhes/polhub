import Foundation
import MailFormat
import Persistence
import UniformTypeIdentifiers

/// What an agent does to Paul's mails besides reading them (16/11): files joined to its draft, a thread filed in a
/// case. Still no network and nothing that sends: the app makes the draft, Paul sends it.
extension MailDesk {
    /// At most this many files in one draft.
    static let maximumFiles = 10

    // MARK: - The files of a draft

    /// A file of the Mac an agent may join, checked whole before anything is copied (Paul, 16/11: « joindre un
    /// fichier à un brouillon »). Never what Paul keeps out of sight: a hidden file or folder (`.ssh`, `.gnupg`, `.env`),
    /// his Library (but iCloud Drive and his cloud drives), a keychain, a key, a secret or a base wherever it lies;
    /// neither directly nor through a link. A regular file, readable, not a folder; 10 files and 25 Mo in all at most
    /// (Gmail's limit). The Library written another way (`~/library`, `/System/Volumes/Data/Users/…`) is still the
    /// Library: Foundation's resolution of the links gives the disk's own path (measured on 19/11).
    func joinable(_ paths: [String]) throws -> [(url: URL, name: String, size: Int)] {
        guard !paths.isEmpty else { return [] }
        guard paths.count <= Self.maximumFiles else {
            throw ToolError("\(paths.count) fichiers : \(Self.maximumFiles) fichiers au plus par brouillon. Rien n'a été déposé.")
        }
        var chosen: [(url: URL, name: String, size: Int)] = [], refusals: [String] = []
        var taken: Set<String> = [], total = 0
        for path in paths {
            do {
                let file = try checked(path)
                let name = AttachmentSafety.uniqueName(file.name, taken: taken)
                taken.insert(name)
                total += file.size
                chosen.append((file.url, name, file.size))
            } catch {
                refusals.append("\(error)")
            }
        }
        guard refusals.isEmpty else { throw ToolError(refusals.joined(separator: "\n") + "\nRien n'a été déposé : retire ces fichiers, ou demande à Paul.") }
        guard total <= MIMEBuilder.maximumFiles else {
            throw ToolError("Les fichiers font \(Self.size(total)) en tout : 25 Mo au plus, la limite de Gmail. Rien n'a été déposé.")
        }
        return chosen
    }

    /// One path: the file it names, after its links, if nothing keeps it from leaving the Mac.
    func checked(_ path: String) throws -> (url: URL, name: String, size: Int) {
        let shown = Self.line(path)
        let expanded = path.hasPrefix("~/") ? home.appending(path: String(path.dropFirst(2))).path(percentEncoded: false) : path
        guard expanded.hasPrefix("/") else { throw ToolError("« \(shown) » : donne le chemin complet du fichier sur le Mac (/Users/…).") }
        let given = URL(fileURLWithPath: expanded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: given.path(percentEncoded: false)) else { throw ToolError("« \(shown) » est introuvable.") }
        let resolved = given.resolvingSymlinksInPath()
        // The path as given, and the file it leads to: a link never opens the way to what is kept out.
        for url in [given, resolved] {
            if isHubData(url) {
                throw ToolError("« \(shown) » est gardé par hub (une pièce jointe d'un mail, une image d'Inspiration) : un agent ne le joint pas. "
                                + "Dis à Paul de le joindre lui-même, depuis le fil.")
            }
            if let hidden = hiddenPart(url) {
                throw ToolError("« \(shown) » est un fichier caché, ou dans un dossier caché (« \(hidden) ») : hub ne le joint pas.")
            }
            if isInLibrary(url) { throw ToolError("« \(shown) » est dans la Bibliothèque de Paul (~/Library) : hub ne le joint pas.") }
            if url.pathComponents.contains(where: { $0.caseInsensitiveCompare("Keychains") == .orderedSame })
                || ["keychain", "keychain-db"].contains(url.pathExtension.lowercased()) {
                throw ToolError("« \(shown) » est un trousseau de clés : hub ne le joint pas.")
            }
        }
        let file: (url: URL, size: Int)
        do {
            file = try AttachmentSafety.joinable(given)
        } catch let refusal as AttachmentSafety.Refusal {
            if case .folder = refusal { throw ToolError("« \(shown) » est un dossier : compresse-le d'abord.") }
            throw ToolError("« \(shown) » ne peut pas être lu.")
        }
        guard FileManager.default.isReadableFile(atPath: file.url.path(percentEncoded: false)) else { throw ToolError("« \(shown) » ne peut pas être lu.") }
        if [given, resolved].contains(where: Self.holdsASecret) {
            throw ToolError("« \(shown) » ressemble à une clé, un secret ou une base de données : hub ne le joint pas. "
                            + "Si Paul le veut, il le joint lui-même depuis le brouillon.")
        }
        return (file.url, given.lastPathComponent, file.size)
    }

    /// The extensions of keys, secrets and bases (audit of 19/11). `.key` is also Keynote's: there its content decides.
    static let secretExtensions: Set<String> = ["pem", "p12", "pfx", "ppk", "kdbx", "env", "sqlite", "sqlite3", "sqlite-wal", "sqlite-shm", "db"]
    /// What a key or a secret holds in its first bytes, wherever it lies and whatever its name (`id_rsa`, `credentials.json`).
    static let secretMarks = ["PRIVATE KEY-----", "\"client_secret\"", "\"private_key\"", "\"refresh_token\""]

    /// A key, a secret or a base, by its extension or by its first 64 Ko. Never shown to anyone: only looked for.
    static func holdsASecret(_ url: URL) -> Bool {
        if secretExtensions.contains(url.pathExtension.lowercased()) { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = String(decoding: (try? handle.read(upToCount: 65_536)) ?? Data(), as: UTF8.self)
        return secretMarks.contains { head.contains($0) }
    }

    /// The first hidden part of a path (« .ssh », « .env »), else `nil`. One exception: a Claude Code worktree,
    /// `<projet>/.claude/worktrees/<nom>/`, a project's own copy where an agent makes its documents (review of 16/11);
    /// the rest of `.claude`, and the home's own, stay out.
    func hiddenPart(_ url: URL) -> String? {
        let parts = url.pathComponents
        let homes = [home.standardizedFileURL.pathComponents, home.resolvingSymlinksInPath().pathComponents]
        var index = 0
        while index < parts.count {
            if parts[index] == ".claude", index + 3 < parts.count, parts[index + 1] == "worktrees", !parts[index + 2].hasPrefix("."),
               !homes.contains(Array(parts.prefix(index))) {
                index += 3
                continue
            }
            if parts[index].hasPrefix(".") { return parts[index] }
            index += 1
        }
        return nil
    }

    /// In hub's own data, beside the base (mails' attachments, Inspiration's images): Paul joins those from the app.
    func isHubData(_ url: URL) -> Bool {
        let data = files.root.deletingLastPathComponent()
        return [data.standardizedFileURL, data.resolvingSymlinksInPath()].contains { root in
            let folder = root.pathComponents
            return folder.count > 1 && url.pathComponents.count > folder.count && Array(url.pathComponents.prefix(folder.count)) == folder
        }
    }

    /// Under `~/Library`, the home being read as given and after its links (`/var` is `/private/var`). Two of its
    /// folders are Paul's documents, which the Finder shows outside the Library: iCloud Drive and the drives of
    /// `CloudStorage` (Google Drive, Dropbox…). The apps' iCloud folders beside iCloud Drive stay out.
    func isInLibrary(_ url: URL) -> Bool {
        let path = url.pathComponents
        func under(_ folder: [String]) -> Bool { path.count >= folder.count && Array(path.prefix(folder.count)) == folder }
        return [home.standardizedFileURL, home.resolvingSymlinksInPath()].contains { home in
            let library = home.pathComponents + ["Library"]
            return under(library) && !under(library + ["CloudStorage"]) && !under(library + ["Mobile Documents", "com~apple~CloudDocs"])
        }
    }

    /// The files copied into the drop's own folder, for the app: what Paul sees is what was joined now, whatever
    /// becomes of the original. A copy that fails takes the folder with it.
    func stage(_ chosen: [(url: URL, name: String, size: Int)], for id: String) throws -> [MailDraftFile] {
        guard !chosen.isEmpty else { return [] }
        let folder = files.agentFolder(id: id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return try chosen.map { item in
                let target = folder.appending(path: item.name)
                try FileManager.default.copyItem(at: item.url, to: target)
                let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? item.size
                let type = UTType(filenameExtension: (item.name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                return MailDraftFile(filename: item.name, mimeType: type, size: size)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw ToolError("Les fichiers n'ont pas pu être copiés pour hub : \(error.localizedDescription)")
        }
    }

    // MARK: - The case of a thread

    /// Files a thread in a case (Paul, 16/11: « ranger un fil dans un projet »): a project, Perso, Newsletters,
    /// Paiements, Services, or none. As Paul's click on its case, in hub only (no Gmail label); but an agent's choice
    /// teaches nothing about the sender: his next mails do not follow, he becomes no contact. Only a thread Paul lets the
    /// agents read.
    public func fileThread(_ which: String, into place: String) throws -> String {
        let rules = try store.filingRules()
        let thread = try find(which, rules: rules)
        let filing = try Self.filing(named: place, projects: projects)
        let before = caseName(thread, rules: rules) ?? "aucune case"
        try store.file(threadKey: thread.id, as: filing, at: now())
        let after: String
        switch filing {
        case .project(let id): after = "le projet « \(rules.projects.first { $0.id == id }?.name ?? place) »"
        case .none: after = "aucune case (il reste dans Personnes)"
        default: after = filing.title ?? place
        }
        let subject = thread.subject.isEmpty ? "(sans objet)" : Self.line(thread.subject)
        return "Fil « \(subject) » [\(thread.threadID)] rangé : \(after) (avant : \(before)). Dans hub seulement : rien ne change dans Gmail, "
            + "et les prochains mails de cet expéditeur ne suivent pas."
    }

    /// « Perso », « Newsletters », « Paiements », « Services », « aucun », else a project's name.
    static func filing(named place: String, projects: ProjectDesk?) throws -> MailFiling {
        switch ProjectNames.tokens(place).joined(separator: " ") {
        case "": throw ToolError("Il manque « projet » : le nom d'un projet, ou Perso, Newsletters, Paiements, Services, ou « aucun ».")
        case "perso": return .perso
        case "newsletters", "newsletter": return .newsletters
        case "paiements", "paiement": return .payments
        case "services", "service": return .services
        case "aucun", "aucune", "aucune case", "sans case": return .none
        default:
            guard let projects else { throw ToolError("Les projets ne sont pas lisibles ici.") }
            return .project(try projects.resolve(place).id)
        }
    }
}
