import Foundation
import Yams

/// What the import read from the vault, before anything goes into the base.
public struct VaultSnapshot: Sendable {
    public var projects: [ImportedProject]
    /// Card order of the « Kanban » view: status → note names, without `.md`.
    public var cardOrder: [String: [String]]
    /// The newest meeting note linked to each project, by note name.
    public var lastMeetings: [String: Date]
    public var warnings: [String]

    public init(projects: [ImportedProject], cardOrder: [String: [String]], lastMeetings: [String: Date], warnings: [String]) {
        self.projects = projects
        self.cardOrder = cardOrder
        self.lastMeetings = lastMeetings
        self.warnings = warnings
    }
}

public struct ImportedProject: Equatable, Sendable {
    public var name: String
    public var relativePath: String
    public var status: String?
    public var client: String?
    public var dueDate: Date?
    public var todo: String?
    public var icon: String?
    public var color: String?
    public var contacts: [String] = []
    public var createdOn: Date?
    public var codeFolder: String?
    public var github: String?
    public var notion: String?
    public var lastActivity: Date?
    public var notes = ""
    public var actions: [ImportedAction] = []
    public var journal: [ImportedJournalEntry] = []
    public var noteModifiedAt: Date?

    public init(name: String, relativePath: String) {
        self.name = name
        self.relativePath = relativePath
    }
}

public struct ImportedAction: Equatable, Sendable {
    public var text: String
    public var done: Bool
    public var addedOn: Date?

    public init(text: String, done: Bool, addedOn: Date?) {
        self.text = text
        self.done = done
        self.addedOn = addedOn
    }
}

public struct ImportedJournalEntry: Equatable, Sendable {
    public var date: Date
    public var title: String
    public var body: String

    public init(date: Date, title: String, body: String) {
        self.date = date
        self.title = title
        self.body = body
    }
}

public enum VaultError: Error, CustomStringConvertible {
    case notAVault(String)

    public var description: String {
        switch self {
        case .notAVault(let path): "Ce dossier n'est pas le coffre Obsidian : « database/Projets » est introuvable dans \(path)."
        }
    }
}

/// `[[X]]` → X, `[[X|Y]]` → Y, `[[X#Titre]]` → X.
public enum WikiLinks {
    public static func plain(_ text: String) -> String {
        text.replacing(#/\[\[([^\]|#]+)(#[^\]|]*)?(\|([^\]]+))?\]\]/#) { match in
            String(match.output.4 ?? match.output.1)
        }
    }

    /// The notes a text links to.
    static func targets(_ text: String) -> [String] {
        text.matches(of: #/\[\[([^\]|#]+)/#).map { String($0.output.1).trimmingCharacters(in: .whitespaces) }
    }
}

/// The dates of the vault: `2026-11-13` or `2026-11-13T10:00`, in the Mac's time zone.
enum VaultDates {
    /// Dates stay text in YAML: the vault's days are local days, not UTC midnights.
    static let resolver = Resolver.default.removing(.timestamp)

    static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
