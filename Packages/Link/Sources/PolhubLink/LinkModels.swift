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
    /// The project it is filed in, by name, and its color (`#RRGGBB`).
    public var project: String?
    public var projectColor: String?
    /// The address of who wrote last, for the color of the line's initial.
    public var sender: String?

    public init(id: String, account: String, subject: String, people: String, snippet: String, date: Date, unread: Bool, messages: Int,
                hasFiles: Bool, project: String?, projectColor: String? = nil, sender: String? = nil) {
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
        self.projectColor = projectColor
        self.sender = sender
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

// MARK: - Writing (lot 3, 20/11)

/// A reply under a thread, to its last message: its sender, or everyone (`all`).
public struct LinkReply: Codable, Sendable, Equatable {
    public var thread: String
    public var all: Bool
    public var text: String

    public init(thread: String, all: Bool, text: String) {
        self.thread = thread
        self.all = all
        self.text = text
    }
}

/// A new mail, from `account` (else the Mac's first mailbox).
public struct LinkNewMail: Codable, Sendable, Equatable {
    public var account: String?
    public var to: [String]
    public var cc: [String]
    public var subject: String
    public var text: String

    public init(account: String?, to: [String], cc: [String], subject: String, text: String) {
        self.account = account
        self.to = to
        self.cc = cc
        self.subject = subject
        self.text = text
    }
}

/// The mail that leaves, while it can still be called back: « Envoi dans 8 s · Annuler ».
public struct LinkSending: Codable, Sendable, Equatable {
    public var draftID: String
    public var subject: String
    /// When it leaves.
    public var at: Date
    /// On its way: too late to call it back.
    public var leaving: Bool

    public init(draftID: String, subject: String, at: Date, leaving: Bool) {
        self.draftID = draftID
        self.subject = subject
        self.at = at
        self.leaving = leaving
    }
}

/// A draft to call back.
public struct LinkCancel: Codable, Sendable, Equatable {
    public var draftID: String

    public init(draftID: String) { self.draftID = draftID }
}

/// A question for Colin.
public struct LinkQuestion: Codable, Sendable, Equatable {
    public var text: String

    public init(text: String) { self.text = text }
}

/// A change of Colin's to undo.
public struct LinkUndo: Codable, Sendable, Equatable {
    public var id: String

    public init(id: String) { self.id = id }
}

public struct LinkColinMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var fromPaul: Bool
    public var text: String
    /// `done`, `answering`, `interrupted`, `failed`.
    public var state: String
    public var date: Date

    public init(id: String, fromPaul: Bool, text: String, state: String, date: Date) {
        self.id = id
        self.fromPaul = fromPaul
        self.text = text
        self.state = state
        self.date = date
    }
}

/// A field of a change: « Statut · Priorité 2 → Priorité 1 ».
public struct LinkChangeField: Codable, Sendable, Equatable {
    public var label: String
    public var before: String?
    public var after: String?

    public init(label: String, before: String?, after: String?) {
        self.label = label
        self.before = before
        self.after = after
    }
}

/// What Colin changed on a project, with « Annuler ».
public struct LinkChange: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var project: String
    public var at: Date
    /// « Après ton mail à Marc, 9:50 ».
    public var note: String?
    public var created: Bool
    public var fields: [LinkChangeField]
    public var undone: Bool

    public init(id: String, project: String, at: Date, note: String?, created: Bool, fields: [LinkChangeField], undone: Bool) {
        self.id = id
        self.project = project
        self.at = at
        self.note = note
        self.created = created
        self.fields = fields
        self.undone = undone
    }
}

/// Colin's thread, as on the Accueil: his state, the messages, what he is writing, what he changed.
public struct LinkColin: Codable, Sendable, Equatable {
    /// « prêt », « répond… », « attend ta visio », « se réveille », « en panne », « à l'arrêt ».
    public var state: String
    public var answering: Bool
    /// The answer being written.
    public var streaming: String
    /// Why he cannot answer, when he cannot.
    public var problem: String?
    public var messages: [LinkColinMessage]
    public var changes: [LinkChange]

    public init(state: String, answering: Bool, streaming: String, problem: String?, messages: [LinkColinMessage], changes: [LinkChange]) {
        self.state = state
        self.answering = answering
        self.streaming = streaming
        self.problem = problem
        self.messages = messages
        self.changes = changes
    }
}

/// Where Apple's push service reaches this iPhone, in hexadecimal.
public struct LinkPushToken: Codable, Sendable, Equatable {
    public var token: String

    public init(token: String) { self.token = token }
}
