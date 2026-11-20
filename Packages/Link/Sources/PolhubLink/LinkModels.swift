import Foundation

/// The Mac answers: who it is, which version it speaks, and which paired iPhone asked.
public struct LinkStatus: Codable, Sendable, Equatable {
    public var version: Int
    /// The Mac's Polhub, « 0.51.0 ».
    public var appVersion: String
    /// The paired iPhone's name, as the Mac knows it.
    public var device: String

    public init(version: Int = LinkAPI.version, appVersion: String, device: String) {
        self.version = version
        self.appVersion = appVersion
        self.device = device
    }
}

/// What went wrong, in Paul's words.
public struct LinkError: Codable, Sendable, Equatable, Error {
    public var message: String

    public init(_ message: String) { self.message = message }
}

// MARK: - Mails

/// A folder of the Mac's sidebar: « Boîte de réception », « Automatiques », « Envoyés », « Brouillons »…
public struct LinkFolder: Codable, Sendable, Equatable, Identifiable {
    /// `inbox`, `notifications`, `sent`, `drafts`, `all`: the Mac's own.
    public var id: String
    public var title: String
    public var unread: Int

    public init(id: String, title: String, unread: Int) {
        self.id = id
        self.title = title
        self.unread = unread
    }
}

public struct LinkPerson: Codable, Sendable, Equatable, Hashable {
    public var name: String?
    public var email: String

    public init(name: String?, email: String) {
        self.name = name
        self.email = email
    }

    /// The name, else the address.
    public var shown: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? email }
}

/// A line of a folder's list.
public struct LinkThread: Codable, Sendable, Hashable, Identifiable {
    /// The Mac's key of the thread (`account|threadID`).
    public var id: String
    public var account: String
    public var subject: String
    /// « Camille, moi », as the Mac's list says it.
    public var people: String
    public var snippet: String
    public var date: Date
    public var unread: Bool
    public var messages: Int
    public var hasFiles: Bool
    /// The project it is filed in, by name.
    public var project: String?

    public init(id: String, account: String, subject: String, people: String, snippet: String, date: Date, unread: Bool, messages: Int,
                hasFiles: Bool, project: String?) {
        self.id = id
        self.account = account
        self.subject = subject
        self.people = people
        self.snippet = snippet
        self.date = date
        self.unread = unread
        self.messages = messages
        self.hasFiles = hasFiles
        self.project = project
    }
}

/// A file of a message.
public struct LinkFile: Codable, Sendable, Equatable, Identifiable {
    /// Its part in the message (`partID`).
    public var id: String
    public var name: String
    public var mimeType: String
    public var size: Int

    public init(id: String, name: String, mimeType: String, size: Int) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.size = size
    }
}

/// A message of a thread, its body as the Mac shows it: an HTML document already made safe (no script, no remote
/// image), to show as it is.
public struct LinkMessage: Codable, Sendable, Equatable, Identifiable {
    /// The Mac's key of the message.
    public var id: String
    public var from: LinkPerson?
    public var to: [LinkPerson]
    public var cc: [LinkPerson]
    public var date: Date
    public var html: String
    public var files: [LinkFile]
    /// « Vérifié par Gmail ».
    public var authenticated: Bool

    public init(id: String, from: LinkPerson?, to: [LinkPerson], cc: [LinkPerson], date: Date, html: String, files: [LinkFile],
                authenticated: Bool) {
        self.id = id
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.html = html
        self.files = files
        self.authenticated = authenticated
    }
}

public struct LinkThreadDetail: Codable, Sendable, Equatable {
    public var thread: LinkThread
    public var messages: [LinkMessage]

    public init(thread: LinkThread, messages: [LinkMessage]) {
        self.thread = thread
        self.messages = messages
    }
}

// MARK: - Calendar

public struct LinkEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var allDay: Bool
    /// The Google account whose calendar it is, and its color (`#RRGGBB`).
    public var account: String
    public var color: String?
    /// The Meet link, to join from the iPhone.
    public var meet: URL?
    public var location: String?
    public var project: String?

    public init(id: String, title: String, start: Date, end: Date, allDay: Bool, account: String, color: String?, meet: URL?,
                location: String?, project: String?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.account = account
        self.color = color
        self.meet = meet
        self.location = location
        self.project = project
    }
}

// MARK: - Projects

public struct LinkProject: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// « priorité 2 », « priorité 1 », « en pause », « terminé »: the Mac's columns, in this order.
    public var status: String
    public var client: String?
    public var due: Date?
    /// « La tâche du moment ».
    public var task: String?
    /// The project's color (`#RRGGBB`).
    public var color: String?

    public init(id: UUID, name: String, status: String, client: String?, due: Date?, task: String?, color: String?) {
        self.id = id
        self.name = name
        self.status = status
        self.client = client
        self.due = due
        self.task = task
        self.color = color
    }
}

public struct LinkAction: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var done: Bool
    public var due: Date?

    public init(id: UUID, text: String, done: Bool, due: Date?) {
        self.id = id
        self.text = text
        self.done = done
        self.due = due
    }
}

public struct LinkJournalEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var title: String
    public var text: String

    public init(id: UUID, date: Date, title: String, text: String) {
        self.id = id
        self.date = date
        self.title = title
        self.text = text
    }
}

public struct LinkProjectDetail: Codable, Sendable, Equatable {
    public var project: LinkProject
    public var notes: String
    public var actions: [LinkAction]
    public var journal: [LinkJournalEntry]
    public var events: [LinkEvent]

    public init(project: LinkProject, notes: String, actions: [LinkAction], journal: [LinkJournalEntry], events: [LinkEvent]) {
        self.project = project
        self.notes = notes
        self.actions = actions
        self.journal = journal
        self.events = events
    }
}

// MARK: - Meetings

public struct LinkMeeting: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var start: Date
    /// How long it lasted, in seconds; nil while it records.
    public var seconds: Int?
    public var project: String?
    public var hasSummary: Bool

    public init(id: UUID, title: String, start: Date, seconds: Int?, project: String?, hasSummary: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.seconds = seconds
        self.project = project
        self.hasSummary = hasSummary
    }
}

/// A turn of a meeting's dialogue: « Moi » or « Les autres ».
public struct LinkTurn: Codable, Sendable, Equatable {
    public var speaker: String
    /// From the start of the recording, in seconds.
    public var start: Int
    public var text: String
    /// « à vérifier »: the transcription may have invented it.
    public var doubtful: Bool

    public init(speaker: String, start: Int, text: String, doubtful: Bool) {
        self.speaker = speaker
        self.start = start
        self.text = text
        self.doubtful = doubtful
    }
}

public struct LinkMeetingDetail: Codable, Sendable, Equatable {
    public var meeting: LinkMeeting
    /// The summary, in markdown.
    public var summary: String?
    public var turns: [LinkTurn]

    public init(meeting: LinkMeeting, summary: String?, turns: [LinkTurn]) {
        self.meeting = meeting
        self.summary = summary
        self.turns = turns
    }
}
