import Foundation
import SwiftUI

/// How tight the mails' list is, as Gmail's « Densité d'affichage » (Paul, 15/11: « calque-toi sur Gmail »):
/// « Par défaut » shows the files of a thread under its line.
public enum MailDensity: String, CaseIterable, Identifiable, Sendable {
    case defaut, confortable, compacte

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .defaut: "Par défaut"
        case .confortable: "Confortable"
        case .compacte: "Compacte"
        }
    }

    /// Above and below the line's text.
    public var padding: CGFloat {
        switch self {
        case .defaut, .confortable: Space.m
        case .compacte: Space.s
        }
    }

    public var showsFiles: Bool { self == .defaut }
}

/// What shows once a thread is archived or deleted, as Gmail's « Avance automatique ».
public enum MailAfterGesture: String, CaseIterable, Identifiable, Sendable {
    case suivant, precedent, liste

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .suivant: "Le fil suivant (plus ancien)"
        case .precedent: "Le fil précédent (plus récent)"
        case .liste: "La liste"
        }
    }
}

/// The size of the Kanban's cards (Paul, 14/11; two sizes since 15/11), a choice in Réglages › Projets. The raw
/// values are those already stored: « medium » for the normal cards, « small » for the compact ones; an old
/// « large » reads as normal.
public enum CardSize: String, CaseIterable, Identifiable, Sendable {
    case medium, small

    public init(stored: String?) {
        self = stored.flatMap(CardSize.init(rawValue:)) ?? .medium
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .medium: "Normales"
        case .small: "Compactes"
        }
    }

    /// A compact card shows its logo, its name and its client, nothing else.
    public var isCompact: Bool { self == .small }

    public var columnWidth: CGFloat {
        switch self {
        case .medium: 272
        case .small: 230
        }
    }

    public var padding: CGFloat {
        switch self {
        case .medium: Space.m + 2
        case .small: Space.s + 2
        }
    }

    public var logoSize: CGFloat {
        switch self {
        case .medium: 30
        case .small: 24
        }
    }
}

/// Every setting of Polhub, its key and its default: the views read them through `@AppStorage(Preferences.Key…)`,
/// the rest through this. New features add theirs here, and a row in Réglages (14/11).
public struct Preferences: @unchecked Sendable {
    public enum Key {
        public static let cardSize = "projets.tailleDesCartes"
        /// Réglages › Projets (15/11): the logos asked of the clients' sites.
        public static let projectLogos = "projets.logosEnLigne"
        public static let defaultAccount = "agenda.agendaParDefaut"
        public static let eventMinutes = "agenda.dureeParDefaut"
        public static let eventMeet = "agenda.meetParDefaut"
        public static let showWeekend = "agenda.weekEnd"
        public static let dayStartHour = "agenda.debutDeJournee"
        public static let summariesEnabled = "reunions.comptesRendus"
        public static let transcriptionLanguage = "reunions.langue"
        public static let reminders = "notifications.rappels"
        public static let reminderMinutes = "notifications.delais"
        public static let remindersMeetOnly = "notifications.visioSeulement"
        public static let newEvents = "notifications.nouveaux"
        public static let unrecorded = "notifications.nonEnregistree"
        public static let summaryReady = "notifications.compteRendu"
        public static let sound = "notifications.son"
        /// Réglages › Mails (14/11): when remote images load; the mailboxes hidden from the list.
        public static let mailImages = "mails.images"
        public static let mailHiddenAccounts = "mails.boitesMasquees"
        public static let mailNotices = "notifications.mails"
        /// Only the mails filed in a project are told (step « Ranger »).
        public static let mailNoticesProjects = "notifications.mails.projets"
        /// The senders Paul left from Polhub, with the day (shown in « Abonnements »).
        /// What the agents read: `tout`, or `projets` (read by `polhub mcp` from the app's preferences).
        public static let mailAgentsScope = "mails.agents.portee"
        /// The new mails whose mailbox Paul has not chosen yet.
        public static let mailUnconfirmed = "mails.boiteAChoisir"
        public static let mailUnsubscribed = "mails.desabonnements"
        /// Réglages › Mails (15/11): the list's density, the days apart, the undo delay, what follows a gesture;
        /// the mails' part of the sidebar, open or closed.
        public static let mailDensity = "mails.densite"
        public static let mailDays = "mails.jours"
        public static let mailUndoSeconds = "mails.delaiAnnulation"
        public static let mailAfterGesture = "mails.apresUnGeste"
        public static let mailSidebarOpen = "mails.barreOuverte"
        /// Réglages › Général (14/11): a mail or a project opens over its list, or in place of it.
        public static let floatingPages = "general.fenetreFlottante"
    }

    public enum Default {
        public static let eventMinutes = 60
        public static let dayStartHour = 8
        /// `auto` lets the engine detect it.
        public static let transcriptionLanguage = "fr"
        /// Ten minutes and one minute before (Paul, 14/11).
        public static let reminderMinutes = "10,1"
        public static let reminderChoices = [30, 15, 10, 5, 1]
        /// Gmail's choices for calling a mail back.
        public static let mailUndoChoices = [5, 10, 20, 30]
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var cardSize: CardSize { CardSize(stored: defaults.string(forKey: Key.cardSize)) }
    /// Polhub asks each client's site for its icon; off, the projects keep their initials.
    public var projectLogos: Bool { flag(Key.projectLogos) }
    /// `nil`: the last one used.
    public var defaultAccount: String? { defaults.string(forKey: Key.defaultAccount).flatMap { $0.isEmpty ? nil : $0 } }
    public var eventMinutes: Int { (defaults.object(forKey: Key.eventMinutes) as? Int) ?? Default.eventMinutes }
    public var eventMeet: Bool { (defaults.object(forKey: Key.eventMeet) as? Bool) ?? true }
    public var showWeekend: Bool { (defaults.object(forKey: Key.showWeekend) as? Bool) ?? true }
    public var dayStartHour: Int { (defaults.object(forKey: Key.dayStartHour) as? Int) ?? Default.dayStartHour }
    public var summariesEnabled: Bool { (defaults.object(forKey: Key.summariesEnabled) as? Bool) ?? true }
    public var reminders: Bool { flag(Key.reminders) }
    /// The minutes before an event a reminder comes, the largest first.
    public var reminderMinutes: [Int] { Self.minutes(defaults.string(forKey: Key.reminderMinutes) ?? Default.reminderMinutes) }
    public var remindersMeetOnly: Bool { (defaults.object(forKey: Key.remindersMeetOnly) as? Bool) ?? false }
    public var newEvents: Bool { flag(Key.newEvents) }
    public var unrecorded: Bool { flag(Key.unrecorded) }
    public var summaryReady: Bool { flag(Key.summaryReady) }
    public var mailNotices: Bool { flag(Key.mailNotices) }
    public var sound: Bool { flag(Key.sound) }
    public var mailDensity: MailDensity { MailDensity(rawValue: defaults.string(forKey: Key.mailDensity) ?? "") ?? .defaut }
    /// The list cut by day (« Aujourd'hui », « Hier »…); Gmail does not.
    public var mailDays: Bool { (defaults.object(forKey: Key.mailDays) as? Bool) ?? false }
    /// The seconds a mail can be called back, one of Gmail's choices.
    public var mailUndoSeconds: Int {
        let value = (defaults.object(forKey: Key.mailUndoSeconds) as? Int) ?? 10
        return Default.mailUndoChoices.contains(value) ? value : 10
    }
    public var mailAfterGesture: MailAfterGesture { MailAfterGesture(rawValue: defaults.string(forKey: Key.mailAfterGesture) ?? "") ?? .suivant }

    private func flag(_ key: String) -> Bool { (defaults.object(forKey: key) as? Bool) ?? true }

    /// « 10,1 » → [10, 1].
    public static func minutes(_ text: String) -> [Int] {
        Array(Set(text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 >= 0 })).sorted(by: >)
    }

    public static func minutesText(_ minutes: [Int]) -> String {
        minutes.sorted(by: >).map(String.init).joined(separator: ",")
    }

    /// `nil`: detected by the engine.
    public var transcriptionLanguage: String? {
        let value = defaults.string(forKey: Key.transcriptionLanguage) ?? Default.transcriptionLanguage
        return value == "auto" ? nil : value
    }
}
