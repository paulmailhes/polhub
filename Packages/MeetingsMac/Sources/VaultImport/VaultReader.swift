import Foundation
import Yams

/// The card order of a kanban view of `Projets.base`.
public enum BaseOrder {
    public static func cardOrder(baseYAML: String, view: String = "Kanban") -> [String: [String]] {
        guard let base = (try? Yams.load(yaml: baseYAML)) as? [String: Any],
              let views = base["views"] as? [[String: Any]],
              let kanban = views.first(where: { ($0["name"] as? String) == view }),
              let orders = (kanban["cardOrders"] as? [String: Any])?["note.statut"] as? [String: Any]
        else { return [:] }
        return orders.mapValues { paths in
            NoteParser.flatten(paths).map { ($0 as NSString).lastPathComponent }.map { $0.hasSuffix(".md") ? String($0.dropLast(3)) : $0 }
        }
    }
}

/// The newest meeting of each project, from the notes of `database/Meet`: their `date`, and the projects
/// they link to (`projet` property, or `[[…]]` in the note, as Obsidian's backlinks). Nothing else is kept.
public enum MeetDates {
    public static func lastMeetings(notes: [(name: String, text: String)], projectNames: Set<String>) -> [String: Date] {
        var last: [String: Date] = [:]
        for note in notes {
            let (frontmatter, _) = NoteParser.split(note.text)
            let properties = frontmatter.flatMap { (try? Yams.load(yaml: $0, VaultDates.resolver)) as? [String: Any] } ?? [:]
            guard let date = VaultDates.date(properties["date"]) else { continue }
            let linked = Set(WikiLinks.targets(note.text)).intersection(projectNames)
            for project in linked where last[project].map({ date > $0 }) ?? true {
                last[project] = date
            }
        }
        return last
    }
}

/// Reads the vault, read-only: `Projets.base`, `database/Projets/*.md`, `database/Meet/*.md`.
public enum VaultReader {
    public static func read(vault: URL) throws -> VaultSnapshot {
        let manager = FileManager.default
        let projectsFolder = vault.appending(path: "database/Projets", directoryHint: .isDirectory)
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: projectsFolder.path(percentEncoded: false), isDirectory: &isFolder), isFolder.boolValue else {
            throw VaultError.notAVault(vault.path(percentEncoded: false))
        }
        var projects: [ImportedProject] = []
        var warnings: [String] = []
        for url in markdownFiles(in: projectsFolder) {
            let name = url.deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                warnings.append("« \(name) » : note illisible, laissée de côté.")
                continue
            }
            var (project, warning) = NoteParser.parse(text, name: name, relativePath: "database/Projets/\(url.lastPathComponent)")
            project.noteModifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            projects.append(project)
            if let warning { warnings.append(warning) }
        }
        let base = (try? String(contentsOf: vault.appending(path: "Projets.base"), encoding: .utf8)) ?? ""
        let meetings = markdownFiles(in: vault.appending(path: "database/Meet", directoryHint: .isDirectory)).compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (name: url.deletingPathExtension().lastPathComponent, text: $0) }
        }
        return VaultSnapshot(
            projects: projects.sorted { $0.name < $1.name },
            cardOrder: BaseOrder.cardOrder(baseYAML: base),
            lastMeetings: MeetDates.lastMeetings(notes: meetings, projectNames: Set(projects.map(\.name))),
            warnings: warnings
        )
    }

    static func markdownFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
