import Domain
import Foundation
import Persistence

/// The rules of the loop (plan of 13/11), as pure functions.
public enum Linker {
    /// Mailboxes of everyone: no company to read in them.
    static let publicDomains: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "outlook.fr", "hotmail.com", "hotmail.fr", "live.com", "live.fr", "msn.com",
        "icloud.com", "me.com", "mac.com", "yahoo.com", "yahoo.fr", "orange.fr", "wanadoo.fr", "free.fr", "sfr.fr", "laposte.net",
        "gmx.fr", "gmx.com", "proton.me", "protonmail.com", "aol.com", "bbox.fr", "neuf.fr", "numericable.fr",
    ]

    /// Google's name for the guest, else one read in the address: `camille.martin@…` → « Camille Martin ».
    public static func name(for attendee: Attendee) -> String {
        if let name = attendee.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, name.lowercased() != attendee.email {
            return name
        }
        let local = attendee.email.split(separator: "@").first.map(String.init) ?? attendee.email
        return local.split(whereSeparator: { $0 == "." || $0 == "_" }).map { word in
            word.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: "-")
        }.joined(separator: " ")
    }

    /// `…@exemple-studio.fr` → « Exemple Studio »; nothing for a public mailbox.
    public static func company(forEmail email: String) -> String? {
        guard let domain = email.lowercased().split(separator: "@").last.map(String.init), !publicDomains.contains(domain) else { return nil }
        var labels = domain.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        labels.removeLast()
        if labels.count >= 2, ["co", "com", "org", "net", "gouv", "ac"].contains(labels.last!) { labels.removeLast() }
        guard let name = labels.last, !name.isEmpty else { return nil }
        return name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// The first rule that answers: Paul's choice, the recorded meeting's project, the series', the one
    /// project shared by the guests, a project's name in the title.
    public static func project(
        for event: CalendarEventRow, meetingProject: UUID?, seriesProjects: [String: UUID], contactProjects: [String: Set<UUID>],
        projects: [(id: UUID, name: String)]
    ) -> (id: UUID, origin: EventProjectOrigin)? {
        if event.projectOrigin == .paul, let id = event.projectID { return (id, .paul) }
        if let meetingProject {
            // The meeting got its project from this event: the reason stays the event's.
            if meetingProject == event.projectID, let origin = event.projectOrigin { return (meetingProject, origin) }
            return (meetingProject, .reunion)
        }
        if let series = event.recurringEventID, let id = seriesProjects[series] { return (id, .serie) }
        let guestProjects = event.guests.compactMap { contactProjects[$0.email] }.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        if guestProjects.count == 1, let id = guestProjects.first { return (id, .invites) }
        if guestProjects.isEmpty, let id = projectNamed(in: event.title, projects: projects) { return (id, .titre) }
        return nil
    }

    /// The one project whose name is in the title, as whole words.
    static func projectNamed(in title: String, projects: [(id: UUID, name: String)]) -> UUID? {
        let words = tokens(title)
        let found = Set(projects.filter { project in
            let name = tokens(project.name)
            guard !name.isEmpty, name.joined().count >= 3, name.count <= words.count else { return false }
            return (0...(words.count - name.count)).contains { Array(words[$0..<$0 + name.count]) == name }
        }.map(\.id))
        return found.count == 1 ? found.first : nil
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// The event a recording starting at `date` belongs to: the same Meet code, from 30 min before its start
    /// to 30 min after its end, the nearest start first (14/11).
    public static func event(forCode code: String?, at date: Date, among events: [CalendarEventRow]) -> CalendarEventRow? {
        guard let code else { return nil }
        let margin: TimeInterval = 30 * 60
        return events.filter {
            !$0.allDay && $0.meetCode == code && date >= $0.startAt.addingTimeInterval(-margin) && date <= $0.endAt.addingTimeInterval(margin)
        }.min { abs($0.startAt.timeIntervalSince(date)) < abs($1.startAt.timeIntervalSince(date)) }
    }

    /// The recording of an event: same Meet code around the same time, else a meeting covering half of
    /// the shorter of the two. An imported meeting is only found by Google's id.
    public static func meeting(for event: CalendarEventRow, among meetings: [MeetingRow]) -> MeetingRow? {
        guard !event.allDay else { return nil }
        let recorded = meetings.filter { $0.source != .imported }
        let margin: TimeInterval = 30 * 60
        if let code = event.meetCode {
            let sameCode = recorded.filter {
                $0.meetCode == code && $0.startedAt >= event.startAt.addingTimeInterval(-margin) && $0.startedAt <= event.endAt.addingTimeInterval(margin)
            }
            if let nearest = sameCode.min(by: { abs($0.startedAt.timeIntervalSince(event.startAt)) < abs($1.startedAt.timeIntervalSince(event.startAt)) }) {
                return nearest
            }
        }
        let scored = recorded.compactMap { meeting -> (MeetingRow, TimeInterval)? in
            guard let end = meeting.endedAt ?? meeting.presumedEndAt, end > meeting.startedAt else { return nil }
            let overlap = min(end, event.endAt).timeIntervalSince(max(meeting.startedAt, event.startAt))
            let shorter = min(end.timeIntervalSince(meeting.startedAt), event.endAt.timeIntervalSince(event.startAt))
            return overlap > 0 && overlap >= shorter / 2 ? (meeting, overlap) : nil
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }
}

/// The loop, applied to the base: after each calendar sync and each finished meeting.
public struct LinkRunner: Sendable {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// One loop at a time: a sync's and a gesture's never interleave (review, Important 3).
    static let running = NSLock()

    public func run(now: Date) throws {
        Self.running.lock()
        defer { Self.running.unlock() }
        // Twice: links made by the first pass (a guest now in a project) can file other events.
        try pass(now: now)
        try pass(now: now)
    }

    func pass(now: Date) throws {
        let calendar = CalendarStore(database), contacts = ContactStore(database), projects = ProjectStore(database), meetings = MeetingStore(database)
        let mine = Set(try calendar.accounts().map(\.email))
        var events = try calendar.allEvents()

        // 1. Guests → contacts.
        for event in events {
            for guest in event.guests where !mine.contains(guest.email) {
                try contacts.upsert(email: guest.email, name: Linker.name(for: guest), company: Linker.company(forEmail: guest.email), at: now)
            }
        }
        let byEmail = Dictionary(try contacts.contacts().compactMap { contact in contact.email.map { ($0, contact) } }, uniquingKeysWith: { first, _ in first })

        // 2. Events ↔ recorded meetings.
        let allMeetings = try meetings.recent(limit: 100_000).filter { $0.status == .ended || $0.status == .interrupted }
        let byGoogleID = Dictionary(try allMeetings.compactMap { meeting in try meetings.googleEventID(meetingID: meeting.id).map { ($0, meeting) } },
                                    uniquingKeysWith: { first, _ in first })
        var taken = Set(events.compactMap(\.meetingID))
        for index in events.indices {
            let event = events[index]
            let found = byGoogleID[event.eventID] ?? (event.meetingID == nil
                ? Linker.meeting(for: event, among: allMeetings.filter { !taken.contains($0.id) }) : nil)
            if let found, found.id != event.meetingID {
                try calendar.setMeeting(eventID: event.id, meetingID: found.id)
                events[index].meetingID = found.id
                taken.insert(found.id)
            }
        }
        let meetingByID = Dictionary(try meetings.recent(limit: 100_000).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 3. Events → projects.
        let projectList = try projects.projects().map { (id: $0.id, name: $0.name) }
        let contactIDs = Dictionary(byEmail.map { ($0.value.id, $0.key) }, uniquingKeysWith: { first, _ in first })
        var contactProjects: [String: Set<UUID>] = [:]
        for link in try contacts.links() where !link.excluded {
            if let email = contactIDs[link.contactID] { contactProjects[email, default: []].insert(link.projectID) }
        }
        var seriesProjects: [String: UUID] = [:]
        for event in events.sorted(by: { ($0.projectOrigin == .paul ? 0 : 1) < ($1.projectOrigin == .paul ? 0 : 1) }) {
            guard let series = event.recurringEventID, let id = event.projectID, [.paul, .reunion].contains(event.projectOrigin) else { continue }
            if seriesProjects[series] == nil { seriesProjects[series] = id }
        }
        for index in events.indices {
            let event = events[index]
            // Paul's filing, « no project » included, is never recomputed (review, Important 2).
            if event.projectOrigin == .paul { continue }
            let meetingProject = event.meetingID.flatMap { meetingByID[$0]?.projectID }
            let found = Linker.project(for: event, meetingProject: meetingProject, seriesProjects: seriesProjects,
                                       contactProjects: contactProjects, projects: projectList)
            if found?.id != event.projectID || found?.origin != event.projectOrigin {
                try calendar.setAutomaticProject(eventID: event.id, projectID: found?.id, origin: found?.origin)
                events[index].projectID = found?.id
                events[index].projectOrigin = found?.origin
            }
        }

        // 4. The recorded meeting takes what the event knows; 5. guests follow the event's project.
        for event in events {
            let guestIDs = event.guests.compactMap { byEmail[$0.email]?.id }
            if let meetingID = event.meetingID, let meeting = meetingByID[meetingID] {
                if meeting.projectID == nil, let projectID = event.projectID { try projects.setProject(meetingID: meetingID, projectID: projectID) }
                if MeetingTitle.isGeneric(meeting.title), !event.title.isEmpty { try meetings.setTitle(meetingID: meetingID, title: event.title) }
                let present = Set(try contacts.participants(meetingID: meetingID).map(\.id))
                if !Set(guestIDs).isSubset(of: present) {
                    try contacts.setParticipants(meetingID: meetingID, contactIDs: Array(present) + guestIDs)
                }
            }
            if let projectID = event.projectID {
                for id in guestIDs { try contacts.link(contactID: id, projectID: projectID, origin: .agenda, at: now) }
            }
        }
    }
}
