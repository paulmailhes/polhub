import Foundation
import Persistence
import PolhubDesign
import SwiftUI

/// The last time Paul and a contact crossed (15/11): a mail, a recorded meeting, an event of the calendars.
struct LastContact: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case mail, meeting, event

        var symbol: String {
            switch self {
            case .mail: "envelope"
            case .meeting: "waveform"
            case .event: "calendar"
            }
        }

        /// « Dernier mail », « Dernière réunion », « Dernier rendez-vous ».
        var title: String {
            switch self {
            case .mail: "Dernier mail"
            case .meeting: "Dernière réunion"
            case .event: "Dernier rendez-vous"
            }
        }
    }

    var date: Date
    var kind: Kind
}

/// What the Contacts section shows, and in which order (15/11): Paul lands there from a mail or a meeting, so
/// the people he crossed lately come first, and a contact's page says in a glance where they stand.
enum ContactsModel {
    // MARK: - The list

    /// Every word typed is found in the name, the address, the company or one of the contact's projects, without
    /// case nor accents: « studio site » finds Camille of Exemple Studio, in « Site vitrine ».
    static func matches(_ contact: ContactRow, projects: [String], query: String) -> Bool {
        let words = PeopleIndex.fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = PeopleIndex.fold(([contact.name, contact.email ?? "", contact.company ?? ""] + projects).joined(separator: " "))
        return words.allSatisfy { text.contains($0) }
    }

    /// The most recent of the three; on the same instant, a mail before a meeting before an event.
    static func last(mail: Date?, meeting: Date?, event: Date?) -> LastContact? {
        let found: [LastContact] = [(mail, LastContact.Kind.mail), (meeting, .meeting), (event, .event)]
            .compactMap { date, kind in date.map { LastContact(date: $0, kind: kind) } }
        return found.max { $0.date < $1.date }
    }

    /// The start of each guest's latest event that has begun: neither Paul, nor a room, nor someone who declined.
    static func lastEvents(_ events: [CalendarEventRow], now: Date) -> [String: Date] {
        var result: [String: Date] = [:]
        for event in events where event.startAt <= now {
            for guest in event.attendees where !guest.isSelf && !guest.isResource && guest.response != "declined" {
                result[guest.email] = max(result[guest.email] ?? .distantPast, event.startAt)
            }
        }
        return result
    }

    /// Each contact's projects, Paul's removals left out, by name. `links`: contact → project → removed.
    static func projects(links: [UUID: [UUID: Bool]], projects: [ProjectRow]) -> [UUID: [ProjectRow]] {
        let byID = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [UUID: [ProjectRow]] = [:]
        for (contact, linked) in links {
            let found = linked.filter { !$0.value }.keys.compactMap { byID[$0] }
            if !found.isEmpty { result[contact] = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        }
        return result
    }

    /// One contact's projects, Paul's removals left out, by name.
    static func projects(of contact: UUID, links: [UUID: [UUID: Bool]], projects: [ProjectRow]) -> [ProjectRow] {
        guard let linked = links[contact] else { return [] }
        return Self.projects(links: [contact: linked], projects: projects)[contact] ?? []
    }

    /// A part of the list.
    struct Section: Identifiable, Equatable {
        let title: String
        var contacts: [ContactRow]
        var id: String { title }
    }

    static let recentWeek = "7 jours précédents"
    static let recentMonth = "30 jours précédents"
    static let earlier = "Plus tôt"
    static let never = "Sans échange"

    /// Those Paul crossed lately first, as Apple's Notes cut by date: « 7 jours précédents », « 30 jours
    /// précédents », « Plus tôt », the most recent first in each; then « Sans échange », by last name. The days counted
    /// by `Words` (lot 10, 20/11).
    static func sections(_ contacts: [ContactRow], last: [UUID: LastContact], now: Date, calendar: Calendar = Words.calendar) -> [Section] {
        var buckets: [String: [ContactRow]] = [:]
        for contact in contacts {
            guard let date = last[contact.id]?.date else {
                buckets[never, default: []].append(contact)
                continue
            }
            let days = Words.days(from: date, to: now, calendar: calendar)
            buckets[days < 7 ? recentWeek : days < 30 ? recentMonth : earlier, default: []].append(contact)
        }
        return [recentWeek, recentMonth, earlier, never].compactMap { title in
            guard let found = buckets[title], !found.isEmpty else { return nil }
            let sorted = title == never
                ? found.sorted { (sortKey($0), $0.name) < (sortKey($1), $1.name) }
                : found.sorted { left, right in
                    let a = last[left.id]?.date ?? .distantPast, b = last[right.id]?.date ?? .distantPast
                    return a == b ? sortKey(left) < sortKey(right) : a > b
                }
            return Section(title: title, contacts: sorted)
        }
    }

    /// By last name, as the vault's « Annuaire ».
    static func sortKey(_ contact: ContactRow) -> String {
        let words = contact.name.replacing(#/\s*\(.*?\)/#, with: "").split(separator: " ").filter { $0.count > 1 }
        return (words.last.map { String($0) } ?? contact.name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Under the name: the company, else the address.
    static func detail(_ contact: ContactRow) -> String? {
        [contact.company, contact.email].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    static func initials(_ contact: ContactRow) -> String {
        PeopleIndex.initials(name: contact.name, email: contact.email ?? contact.name)
    }

    /// The person's color, the same as in the mails.
    static func tint(_ contact: ContactRow) -> Color {
        MailText.tint(for: contact.email ?? contact.name)
    }

    /// At the end of a row, a meta (lot 10, 20/11): « aujourd'hui », « hier », « lun. » within the week, « 12 nov. » this
    /// year, « 12 nov. 2025 » before; no longer « 12/11/25 ».
    static func when(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        Words.shortDay(date, now: now, calendar: calendar)
    }

    // MARK: - A contact's page

    /// « aujourd'hui », « hier », « il y a 3 jours », « il y a 2 semaines », « il y a 4 mois », « il y a 1 an »: by
    /// `Words` (lot 10, 20/11).
    static func ago(_ date: Date, now: Date, calendar: Calendar = Words.calendar) -> String {
        Words.daysAgo(date, now: now, calendar: calendar)
    }

    /// « Dernier mail il y a 3 jours ».
    static func lastText(_ last: LastContact, now: Date, calendar: Calendar = Words.calendar) -> String {
        "\(last.kind.title) \(ago(last.date, now: now, calendar: calendar))"
    }

    /// The events with this address: those to come (or under way), the soonest first; then the others, the latest
    /// first.
    static func events(_ events: [CalendarEventRow], of email: String?, now: Date) -> (coming: [CalendarEventRow], past: [CalendarEventRow]) {
        guard let email = email?.lowercased(), !email.isEmpty else { return ([], []) }
        let mine = events.filter { $0.attendees.contains { $0.email == email } }
        return (mine.filter { $0.endAt > now }.sorted { $0.startAt < $1.startAt },
                mine.filter { $0.endAt <= now }.sorted { $0.startAt > $1.startAt })
    }

    /// « Rendez-vous en cours », « Rendez-vous aujourd'hui 14:00 », « … demain 9:30 », « … jeudi 14:00 » within the
    /// week, « … mercredi 25 à 14:00 », « … mercredi 2 décembre à 14:00 » after; a whole day, « Rendez-vous demain »,
    /// « Rendez-vous lundi 30 ». The day and the hour by `Words` (lot 10, 20/11).
    static func nextText(_ event: CalendarEventRow, now: Date, calendar: Calendar = Words.calendar) -> String {
        if event.startAt <= now { return "Rendez-vous en cours" }
        if event.allDay { return "Rendez-vous " + Words.day(event.startAt, now: now, calendar: calendar) }
        return "Rendez-vous " + Words.moment(event.startAt, now: now, calendar: calendar)
    }

    /// Under an event's title: « Aujourd'hui, 14:00 – 15:00 », « Demain, 9:30 – 10:00 », « Jeu., 14:00 – 15:00 »
    /// within the week, « 20 nov., 14:00 – 15:00 », the year when it is not this one; « Demain, toute la journée » for a
    /// whole day. By `Words` (lot 10, 20/11).
    static func eventWhen(_ event: CalendarEventRow, now: Date, calendar: Calendar = Words.calendar) -> String {
        let day = Words.capitalizedFirst(Words.shortDay(event.startAt, now: now, calendar: calendar))
        if event.allDay { return day + ", " + Words.allDay }
        return day + ", " + Words.timeRange(from: event.startAt, to: event.endAt, calendar: calendar)
    }

    /// Under a meeting's title: « 12 nov., 14:00 · 45 min », the year when it is not this one; the length as the list
    /// of the meetings says it. By `Words` (lot 10, 20/11).
    static func meetingWhen(_ meeting: MeetingRow, now: Date, calendar: Calendar = Words.calendar) -> String {
        let date = Words.shortDate(meeting.startedAt, now: now, calendar: calendar) + ", " + Words.time(meeting.startedAt, calendar: calendar)
        guard let end = meeting.endedAt, end > meeting.startedAt else { return date }
        return date + " · " + Words.duration(Int(end.timeIntervalSince(meeting.startedAt)))
    }
}
