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

    /// The narrowest a column gets; wider windows share their width between the four columns (Paul, 15/11).
    public var columnWidth: CGFloat {
        switch self {
        case .medium: 260
        case .small: 230
        }
    }

    public var padding: CGFloat {
        switch self {
        case .medium: Space.m + 2
        case .small: Space.s + 2
        }
    }

    /// The same in every column, Terminé included (Paul, 15/11).
    public var logoSize: CGFloat { 36 }
}

/// Every setting of hub, its key and its default: the views read them through `@AppStorage(Preferences.Key…)`,
/// the rest through this. New features add theirs here, and a row in Réglages (14/11).
public struct Preferences: @unchecked Sendable {
    public enum Key {
        /// Whether the relaunch agent was on, noted at each launch (0.57.1): the version that changes its name (hub.app
        /// → hub.app, 20/11) registers it again from its new place.
        public static let relaunchHint = "relanceActive"
        public static let cardSize = "projets.tailleDesCartes"
        /// Réglages › Projets (15/11): the logos asked of the clients' sites.
        public static let projectLogos = "projets.logosEnLigne"
        public static let defaultAccount = "agenda.agendaParDefaut"
        public static let eventMinutes = "agenda.dureeParDefaut"
        public static let eventMeet = "agenda.meetParDefaut"
        public static let showWeekend = "agenda.weekEnd"
        public static let dayStartHour = "agenda.debutDeJournee"
        /// Réglages › Calendrier (0.36.0): from when, in minutes after midnight, the Accueil shows tomorrow.
        public static let homeTomorrowFrom = "accueil.demainAPartirDe"
        public static let summariesEnabled = "reunions.comptesRendus"
        public static let transcriptionLanguage = "reunions.langue"
        public static let reminders = "notifications.rappels"
        public static let reminderMinutes = "notifications.delais"
        public static let remindersMeetOnly = "notifications.visioSeulement"
        /// Réglages › Notifications (16/11): the card that stays at the top right before a Meet, and how long before.
        public static let meetingCard = "notifications.carteAvantVisio"
        public static let meetingCardMinutes = "notifications.carteAvantVisio.minutes"
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
        /// The senders Paul left from hub, with the day (shown in « Abonnements »).
        /// What the agents read: `tout`, or `projets` (read by `hub mcp` from the app's preferences).
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
        /// « Plus » under Mails in the sidebar, unfolded by Paul (lot 4, 19/11); it unfolds by itself on a folder of its own.
        public static let mailMoreOpen = "mails.plusOuvert"
        /// Réglages › Général (14/11): a mail or a project opens over its list, or in place of it.
        public static let floatingPages = "general.fenetreFlottante"
        /// Réglages › Général (15/11): « 8 min » beside the logo in the quarter of an hour before a Meet.
        public static let menuBarMeetMinutes = "general.minutesAvantUnMeet"
        /// Réglages › Inspiration (16/11): the automatic collection (Awwwards, LinkedIn), the categories by Apple's
        /// AI.
        public static let inspirationAutoCollect = "inspiration.collecteAuto"
        public static let inspirationAICategories = "inspiration.categoriesIA"
        /// Réglages › Diagnostic (17/11): the folder of the Claude account Colin uses; empty, Claude Code's own.
        public static let colinAccount = "colin.dossierDuCompte"
        /// Colin's bar (18/11): on or off, the one switch of the Accueil and of Réglages › Colin. Off by default.
        public static let colinOn = "colin.enMarche"
        /// « Colin tient le kanban seul » (step 3, 18/11): the two rules after a send and after a booking; and since when.
        public static let colinKanban = "colin.tableauSeul"
        public static let colinKanbanSince = "colin.tableauSeul.depuis"
        /// The version of the app that last counted Colin's rules on the mails (18/11).
        public static let colinRulesCount = "colin.releveDesRegles"
        /// Réglages › Colin (18/11): the days after which the Accueil signals a mail left without an answer, and a
        /// client who no longer answers.
        public static let colinReplyDays = "colin.reponseAttendue.jours"
        public static let colinSilentDays = "colin.clientMuet.jours"
        /// Réglages › Notifications › Colin (18/11): « Un brouillon est prêt ».
        public static let colinDraftNotice = "notifications.colin.brouillon"
        /// When the Accueil was last before Paul, and since when (18/11): three dates.
        public static let colinPresence = "colin.presence"
        /// How long Paul was away from the Accueil, in minutes, from half an hour up, the last hundred: numbers
        /// only, to set the threshold of a return.
        public static let colinAbsences = "colin.presence.absences"
    }

    public enum Default {
        public static let eventMinutes = 60
        public static let dayStartHour = 8
        public static let homeTomorrowFrom = 19 * 60
        /// `auto` lets the engine detect it.
        public static let transcriptionLanguage = "fr"
        /// Ten minutes and one minute before (Paul, 14/11).
        public static let reminderMinutes = "10,1"
        public static let reminderChoices = [30, 15, 10, 5, 1]
        /// The card before a Meet: two minutes before (Paul, 16/11: « une minute avant ou deux minutes avant même »).
        public static let meetingCardMinutes = 2
        public static let meetingCardChoices = [1, 2, 5]
        /// Gmail's choices for calling a mail back.
        public static let mailUndoChoices = [5, 10, 20, 30]
        /// A mail left without an answer is signaled after three days, a silent client after seven (the design of
        /// 17/11).
        public static let colinReplyDays = 3
        public static let colinReplyChoices = [2, 3, 5, 7]
        public static let colinSilentDays = 7
        public static let colinSilentChoices = [5, 7, 10, 14]
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var cardSize: CardSize { CardSize(stored: defaults.string(forKey: Key.cardSize)) }
    /// hub asks each client's site for its icon; off, the projects keep their initials.
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
    public var meetingCard: Bool { flag(Key.meetingCard) }
    public var meetingCardMinutes: Int { (defaults.object(forKey: Key.meetingCardMinutes) as? Int) ?? Default.meetingCardMinutes }
    public var newEvents: Bool { flag(Key.newEvents) }
    public var unrecorded: Bool { flag(Key.unrecorded) }
    public var summaryReady: Bool { flag(Key.summaryReady) }
    public var mailNotices: Bool { flag(Key.mailNotices) }
    /// Colin answers in the bar (off by default: turned on by the user).
    public var colinOn: Bool { (defaults.object(forKey: Key.colinOn) as? Bool) ?? false }
    /// « Colin tient le kanban seul » (step 3, 18/11): off until Paul turns it on.
    public var colinKanban: Bool { (defaults.object(forKey: Key.colinKanban) as? Bool) ?? false }
    /// Colin says a draft an agent prepared is ready (on by default).
    public var colinDraftNotice: Bool { flag(Key.colinDraftNotice) }
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
    /// The days after which a mail without an answer is signaled: one of the choices, or the default.
    public var colinReplyDays: Int { choice(Key.colinReplyDays, among: Default.colinReplyChoices, or: Default.colinReplyDays) }
    /// The days after which a silent client is signaled: one of the choices, or the default.
    public var colinSilentDays: Int { choice(Key.colinSilentDays, among: Default.colinSilentChoices, or: Default.colinSilentDays) }
    /// The minutes before a Meet in the menu bar (Paul, 15/11: on by default).
    public var menuBarMeetMinutes: Bool { flag(Key.menuBarMeetMinutes) }
    /// hub collects the new sites and posts by itself (on by default; never in the development build, which
    /// the scheduler decides).
    public var inspirationAutoCollect: Bool { flag(Key.inspirationAutoCollect) }
    /// Apple's on-device model proposes the categories of a new item (on by default).
    public var inspirationAICategories: Bool { flag(Key.inspirationAICategories) }

    private func flag(_ key: String) -> Bool { (defaults.object(forKey: key) as? Bool) ?? true }

    /// A value among its choices, or the default: what nobody could have chosen is never applied.
    public static func choice(_ value: Int?, among choices: [Int], or fallback: Int) -> Int {
        value.flatMap { choices.contains($0) ? $0 : nil } ?? fallback
    }

    private func choice(_ key: String, among choices: [Int], or fallback: Int) -> Int {
        Self.choice(defaults.object(forKey: key) as? Int, among: choices, or: fallback)
    }

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
