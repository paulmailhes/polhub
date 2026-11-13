import Domain
import Foundation
import Persistence
import Yams

// The vault's contacts (`database/Contacts`) and old meetings (`database/Meet`), added to the app without
// replacing anything: the projects are not touched, and a second import updates instead of duplicating
// (13/11). The vault is only read.

public struct ImportedContact: Equatable, Sendable {
    public var name: String
    public var relativePath: String
    public var email: String?
    public var company: String?
    public var phone: String?
    public var projects: [String] = []
    public var notes = ""
}

public struct ImportedMeeting: Equatable, Sendable {
    public var title: String
    public var relativePath: String
    public var date: Date?
    public var participants: [String] = []
    public var project: String?
    public var eventID: String?
    public var summary = ""
    public var actions: [ImportedAction] = []
    /// One paragraph per item, voices not told apart.
    public var transcript: [String] = []
}

public struct HistorySnapshot: Sendable {
    public var contacts: [ImportedContact]
    public var meetings: [ImportedMeeting]
    public var warnings: [String]
}

public struct HistoryReport: Equatable, Sendable {
    public var contacts = 0
    /// Meetings created or updated, merged ones included.
    public var meetings = 0
    /// Vault notes of a meeting Polhub recorded itself: that meeting is completed, not duplicated.
    public var merged = 0
    public var warnings: [String] = []

    /// « 94 contacts, 33 réunions (dont 1 déjà enregistrée par Polhub) ».
    public var summary: String {
        var text = "\(contacts) contact\(contacts > 1 ? "s" : ""), \(meetings) réunion\(meetings > 1 ? "s" : "")"
        if merged > 0 { text += " (dont \(merged) déjà enregistrée\(merged > 1 ? "s" : "") par Polhub)" }
        if !warnings.isEmpty { text += " ; \(warnings.count) avertissement\(warnings.count > 1 ? "s" : "")" }
        return text
    }
}

public enum HistoryNotes {
    static func properties(_ raw: String) -> ([String: Any], String) {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let (frontmatter, body) = NoteParser.split(text)
        let properties = frontmatter.flatMap { (try? Yams.load(yaml: $0, VaultDates.resolver)) as? [String: Any] } ?? [:]
        return (properties, body)
    }

    static func text(_ properties: [String: Any], _ key: String) -> String? {
        guard let value = NoteParser.flatten(properties[key]).first else { return nil }
        let plain = WikiLinks.plain(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return plain.isEmpty ? nil : plain
    }

    static func list(_ properties: [String: Any], _ key: String) -> [String] {
        NoteParser.flatten(properties[key]).map { WikiLinks.plain($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public static func contact(_ raw: String, name: String, relativePath: String) -> ImportedContact {
        let (properties, body) = properties(raw)
        var contact = ImportedContact(name: name, relativePath: relativePath)
        contact.email = text(properties, "email")?.lowercased()
        contact.company = text(properties, "entreprise")
        contact.phone = text(properties, "telephone")
        contact.projects = list(properties, "projets")
        // The `mailto:` line the vault writes under the properties is not a note.
        contact.notes = body.components(separatedBy: "\n")
            .filter { !$0.contains("](mailto:") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return contact
    }

    public static func meeting(_ raw: String, name: String, relativePath: String) -> ImportedMeeting {
        let (properties, body) = properties(raw)
        // « 2026-10-20 10h00 Titre » or « 2026-10-20 Titre ».
        let fallback = name.replacing(#/^\d{4}-\d{2}-\d{2}(\s+\d{1,2}h\d{2})?\s*/#, with: "")
        var meeting = ImportedMeeting(title: text(properties, "titre") ?? (fallback.isEmpty ? name : fallback), relativePath: relativePath)
        meeting.date = VaultDates.date(properties["date"])
        meeting.participants = list(properties, "participants")
        meeting.project = text(properties, "projet")
        meeting.eventID = text(properties, "evenement")
        let sections = NoteParser.sections(body)
        meeting.summary = sections.filter { $0.title == "Résumé" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
        meeting.actions = sections.filter { $0.title == "Actions" }.flatMap { NoteParser.actions($0.text) }
        let notes = sections.filter { $0.title == "Notes" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("_Rien pour l") }
        if !notes.isEmpty { meeting.summary += (meeting.summary.isEmpty ? "" : "\n\n") + "### Notes de Paul\n" + notes.joined(separator: "\n\n") }
        meeting.transcript = sections.filter { $0.title == "Transcription" }.flatMap { transcript($0.text) }
        return meeting
    }

    /// The callout `> [!note]- Texte intégral`, its `> ` removed, cut at its empty lines.
    static func transcript(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        func close() {
            let paragraph = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            current = []
        }
        for line in text.components(separatedBy: "\n") {
            let content = line.hasPrefix(">") ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line.trimmingCharacters(in: .whitespaces)
            if content.hasPrefix("[!") { continue }
            if content.isEmpty { close() } else { current.append(content) }
        }
        close()
        return paragraphs
    }
}

public enum HistoryReader {
    public static func read(vault: URL) throws -> HistorySnapshot {
        let database = vault.appending(path: "database", directoryHint: .isDirectory)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: database.path(percentEncoded: false), isDirectory: &isFolder), isFolder.boolValue else {
            throw VaultError.notAVault(vault.path(percentEncoded: false))
        }
        var warnings: [String] = []
        func notes(_ folder: String) -> [(name: String, path: String, text: String)] {
            VaultReader.markdownFiles(in: database.appending(path: folder, directoryHint: .isDirectory)).compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                    warnings.append("« \(url.lastPathComponent) » : note illisible, laissée de côté.")
                    return nil
                }
                return (url.deletingPathExtension().lastPathComponent, "database/\(folder)/\(url.lastPathComponent)", text)
            }
        }
        let contacts = notes("Contacts").map { HistoryNotes.contact($0.text, name: $0.name, relativePath: $0.path) }
        let meetings = notes("Meet").map { HistoryNotes.meeting($0.text, name: $0.name, relativePath: $0.path) }
        return HistorySnapshot(contacts: contacts, meetings: meetings, warnings: warnings)
    }
}

public enum HistoryImport {
    /// A vault note within this many seconds of a meeting Polhub recorded is that meeting.
    static let sameMeeting: TimeInterval = 15 * 60

    public static func apply(_ snapshot: HistorySnapshot, database: AppDatabase, now: Date) throws -> HistoryReport {
        let contacts = ContactStore(database)
        let projects = ProjectStore(database)
        let meetings = MeetingStore(database)
        let transcripts = TranscriptStore(database)
        let projectByName = Dictionary(try projects.projects().map { (fold($0.name), $0.id) }, uniquingKeysWith: { first, _ in first })
        var report = HistoryReport(warnings: snapshot.warnings)

        // Contacts: by their note, else their address, else their name.
        var known = try contacts.contacts()
        for imported in snapshot.contacts {
            var contact = known.first { $0.importedFrom == imported.relativePath }
                ?? imported.email.flatMap { email in known.first { $0.email == email } }
                ?? known.first { fold($0.name) == fold(imported.name) }
                ?? ContactRow(name: imported.name, createdAt: now)
            contact.name = imported.name
            contact.email = imported.email ?? contact.email
            contact.company = imported.company ?? contact.company
            contact.phone = imported.phone ?? contact.phone
            if !imported.notes.isEmpty { contact.notes = imported.notes }
            contact.importedFrom = imported.relativePath
            contact.deletedAt = nil
            try contacts.save(contact, at: now)
            for name in imported.projects {
                guard let projectID = projectByName[fold(name)] else { continue }
                try contacts.link(contactID: contact.id, projectID: projectID, origin: .coffre, at: now)
            }
            report.contacts += 1
            known = try contacts.contacts()
        }

        // Meetings.
        let recorded = try meetings.recent(limit: 100_000).filter { $0.source != .imported }
        for imported in snapshot.meetings {
            guard let date = imported.date else {
                report.warnings.append("« \(imported.title) » : pas de date, laissée de côté.")
                continue
            }
            let projectID = imported.project.flatMap { projectByName[fold($0)] }
            var participantIDs: [UUID] = []
            for name in imported.participants {
                if let contact = known.first(where: { fold($0.name) == fold(name) }) {
                    participantIDs.append(contact.id)
                } else {
                    let contact = ContactRow(name: name, createdAt: now)
                    try contacts.save(contact, at: now)
                    known.append(contact)
                    participantIDs.append(contact.id)
                }
            }
            let meetingID: UUID
            if let twin = recorded.first(where: { abs($0.startedAt.timeIntervalSince(date)) <= sameMeeting }) {
                // Polhub recorded it: its own transcript stays; the vault adds what it lacks.
                meetingID = twin.id
                if MeetingTitle.isGeneric(twin.title) { try meetings.setTitle(meetingID: twin.id, title: imported.title) }
                if twin.projectID == nil, let projectID { try projects.setProject(meetingID: twin.id, projectID: projectID) }
                if (try meetings.summary(meetingID: twin.id)) == nil, !imported.summary.isEmpty {
                    try meetings.setSummary(meetingID: twin.id, summary: imported.summary)
                }
                if let eventID = imported.eventID { try meetings.setGoogleEventID(meetingID: twin.id, eventID: eventID) }
                report.merged += 1
            } else {
                let existing = try meetings.importedMeeting(from: imported.relativePath)
                let row = MeetingRow(
                    id: existing?.id ?? UUID(), createdAt: existing?.createdAt ?? now, updatedAt: now, status: .ended, source: .imported,
                    candidateKey: "coffre/\(imported.relativePath)", title: imported.title, startedAt: date,
                    transcribedAt: imported.transcript.isEmpty ? nil : date, projectID: projectID
                )
                try meetings.saveImported(row, importedFrom: imported.relativePath, googleEventID: imported.eventID,
                                          summary: imported.summary.isEmpty ? nil : imported.summary)
                try projects.setProject(meetingID: row.id, projectID: projectID)
                try transcripts.replaceUtterances(meetingID: row.id, imported.transcript.enumerated().map { index, text in
                    UtteranceRow(meetingID: row.id, speaker: .unknown, startMs: index * 1_000, endMs: index * 1_000 + 999, text: text, doubtful: false)
                })
                meetingID = row.id
            }
            try contacts.setParticipants(meetingID: meetingID, contactIDs: participantIDs + (try contacts.participants(meetingID: meetingID).map(\.id)))
            try projects.replaceMeetingActions(meetingID: meetingID, projectID: try meetings.meeting(id: meetingID)?.projectID,
                                               actions: imported.actions.enumerated().map { index, action in
                                                   ActionRow(meetingID: meetingID, text: action.text, done: action.done, addedOn: action.addedOn,
                                                             position: 10_000 + Double(index), createdAt: now)
                                               })
            report.meetings += 1
        }
        return report
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespaces)
    }
}
