import Agenda
import AppKit
import Domain
import Persistence
import ProjectsUI
import HubDesign
import SwiftUI
import Updates

/// The sidebar keeps the work; the app's own pages (diagnostic, journal) live in Réglages (Paul, 13/11).
public enum SidebarItem: String, Hashable, Sendable {
    case home, projects, meetings, calendar, mails, contacts, inspiration, dictation, vigie, settings

    var title: String {
        switch self {
        case .home: "Accueil"
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .contacts: "Contacts"
        case .inspiration: "Inspiration"
        case .dictation: "Dictée"
        case .vigie: "Vigie"
        case .settings: "Réglages"
        }
    }

    /// Its icon in the sidebar, from Phosphor (Paul, 15/11: « des icônes beaucoup mieux »).
    var appIcon: AppIcon {
        switch self {
        case .home: .home
        case .projects: .projects
        case .meetings: .meetings
        case .calendar: .calendar
        case .mails: .mails
        case .contacts: .contacts
        case .inspiration: .inspiration
        case .dictation: .dictation
        case .vigie: .vigie
        case .settings: .settings
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .projects: "square.grid.3x2.fill"
        case .meetings: "mic.fill"
        case .calendar: "calendar"
        case .mails: "envelope.fill"
        case .contacts: "person.2.fill"
        case .inspiration: "lightbulb.fill"
        case .dictation: "waveform"
        case .vigie: "binoculars.fill"
        case .settings: "gearshape.fill"
        }
    }

    /// One color per section, as in Mail's and the Finder's sidebar; the same as its family in Réglages (15/11).
    var tint: String {
        switch self {
        case .home: Palette.teal
        case .projects: Palette.blue
        case .meetings: Palette.violet
        case .calendar: Palette.orange
        case .mails: Palette.pink
        case .contacts: Palette.green
        case .inspiration: Palette.yellow
        case .dictation: Palette.indigo
        case .vigie: Palette.cyan
        case .settings: Palette.gray
        }
    }

    /// The work, in the sidebar's list; Réglages sits apart, at the bottom (Paul, 14/11). Accueil, Calendrier and
    /// Contacts need the agenda (13/11). « Inspiration » on one row, after Mails; Contacts at the bottom, with Réglages
    /// (lot 4, 19/11: « Mails court »).
    /// Réunions only when its add-on is installed (20/11).
    /// Dictée last (20/11): the keys ⌘1 to ⌘7 of the others do not move, and it has none. Vigie after it (21/11), the same.
    static func visible(hasProjects: Bool, hasAgenda: Bool, hasMails: Bool = false, hasInspiration: Bool = false,
                        hasMeetings: Bool = true, hasDictation: Bool = false, hasVigie: Bool = false) -> [SidebarItem] {
        [hasAgenda ? .home : nil, hasProjects ? .projects : nil, hasMeetings ? .meetings : nil, hasAgenda ? .calendar : nil,
         hasMails ? .mails : nil, hasInspiration ? .inspiration : nil, hasDictation ? .dictation : nil, hasVigie ? .vigie : nil].compactMap { $0 }
    }

    /// The rows at the bottom of the sidebar, apart from the work (lot 4, 19/11): Contacts, then Réglages.
    static func footer(hasAgenda: Bool) -> [SidebarItem] {
        [hasAgenda ? .contacts : nil, .settings].compactMap { $0 }
    }

    /// ⌘1 to ⌘7 (lot 4, 19/11): the sidebar's rows from top to bottom, Réglages apart (⌘,). Computed from its list, in
    /// the window and in « Coup d'œil » alike: never a number written by hand.
    public static func numbered(hasProjects: Bool, hasAgenda: Bool, hasMails: Bool = false, hasInspiration: Bool = false) -> [SidebarItem] {
        visible(hasProjects: hasProjects, hasAgenda: hasAgenda, hasMails: hasMails, hasInspiration: hasInspiration)
            + footer(hasAgenda: hasAgenda).filter { $0 != .settings }
    }

    /// The sidebar of the app, every section there: what « Coup d'œil » numbers, and what its help texts say.
    static let allNumbered = numbered(hasProjects: true, hasAgenda: true, hasMails: true, hasInspiration: true)

    /// Its key, ⌘ and this number (lot 4, 19/11); none for Réglages, which has ⌘,.
    var shortcut: Int? {
        Self.allNumbered.firstIndex(of: self).map { $0 + 1 }
    }
}

/// The families of Réglages, entered one by one, as in Apple's settings (Paul, 14/11). Every new feature puts
/// its settings in its family.
public enum SettingsPane: String, Hashable, Sendable, CaseIterable {
    case addOns, general, accounts, iphone, calendar, mails, colin, projects, meetings, inspiration, dictation, vigie, diagnostic, journal

    public var title: String {
        switch self {
        case .addOns: "Add-ons"
        case .general: "Général"
        case .accounts: "Comptes Google"
        case .iphone: "iPhone"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .colin: "Colin"
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .inspiration: "Inspiration"
        case .dictation: "Dictée"
        case .vigie: "Vigie"
        case .diagnostic: "Diagnostic"
        case .journal: "Journal"
        }
    }

    var icon: String {
        switch self {
        case .addOns: "puzzlepiece.extension.fill"
        case .general: "gearshape.fill"
        case .accounts: "person.crop.circle.fill"
        case .iphone: "iphone"
        case .calendar: "calendar"
        case .mails: "envelope.fill"
        case .colin: "sparkles"
        case .projects: "square.grid.3x2.fill"
        case .meetings: "mic.fill"
        case .inspiration: "lightbulb.fill"
        case .dictation: "waveform"
        case .vigie: "binoculars.fill"
        case .diagnostic: "stethoscope"
        case .journal: "list.bullet.rectangle.fill"
        }
    }

    /// Its badge's glyph (21/11, Paul: « il faudrait que ce soit les mêmes logos »): the sidebar's for the tools, Phosphor
    /// for hub's own pages.
    var appIcon: AppIcon {
        switch self {
        case .addOns: .addOns
        case .general: .settings
        case .accounts: .accounts
        case .iphone: .iphone
        case .calendar: .calendar
        case .mails: .mails
        case .colin: .colin
        case .projects: .projects
        case .meetings: .meetings
        case .inspiration: .inspiration
        case .dictation: .dictation
        case .vigie: .vigie
        case .diagnostic: .diagnostic
        case .journal: .journal
        }
    }

    var tint: String {
        switch self {
        case .addOns: Palette.blue
        case .general: Palette.gray
        case .accounts: Palette.teal
        // Grey since 21/11: beside Projets' blue in the add-ons' list, a family is found by its color.
        case .iphone: Palette.gray
        case .calendar: Palette.orange
        case .mails: Palette.pink
        case .colin: Palette.green
        case .projects: Palette.blue
        case .meetings: Palette.violet
        case .inspiration: Palette.yellow
        case .dictation: Palette.indigo
        case .vigie: Palette.cyan
        case .diagnostic: Palette.green
        case .journal: Palette.brown
        }
    }

    /// What the family's page holds (lot 10, 20/11: Mails, Colin, Projets and Journal said their page again; « kanban »
    /// in a sentence, « hub », never « l'app »).
    var subtitle: String {
        switch self {
        case .addOns: "Ce que hub sait faire, à installer ou à retirer"
        case .general: "Ouverture à la session, notifications, mises à jour, journal"
        case .accounts: "Comptes, couleurs, accès à l'agenda et aux mails"
        case .iphone: "Accès depuis ton iPhone, iPhone reliés"
        case .calendar: "Nouveaux rendez-vous, affichage, rappels"
        case .mails: "Liste, images, envoi, agents, notifications, tri"
        case .colin: "Marche, ce qu'il sait, ce qu'il signale"
        case .projects: "Taille des cartes du kanban"
        case .meetings: "Comptes rendus, langue, notifications"
        case .inspiration: "Pages LinkedIn, collecte, catégories"
        case .dictation: "Touche, fenêtre, texte, son, historique"
        case .vigie: "Auto-accept, questions, garde-fous, moteur"
        case .diagnostic: "Autorisations et connexions, pour chaque outil"
        case .journal: "Ce que hub a fait et vu"
        }
    }

    /// hub's own pages, under the add-ons (21/11, Paul: « moins de pages, des trucs bien rassemblés »): the Google accounts
    /// with the agenda, the Diagnostic (everything to allow or connect, for each tool), Général.
    static func hubPanes(hasAgenda: Bool) -> [SettingsPane] {
        [hasAgenda ? .accounts : nil, .diagnostic, .general].compactMap { $0 }
    }

    /// The families as before 21/11, still read by the tests: Add-ons, the tools installed, hub's own.
    static func families(hasAgenda: Bool, hasProjects: Bool, hasMails: Bool = false, hasInspiration: Bool = false,
                         hasMeetings: Bool = true, hasColin: Bool = true, hasPhone: Bool = true, hasDictation: Bool = false) -> [[SettingsPane]] {
        let work = SidebarItem.visible(hasProjects: hasProjects, hasAgenda: hasAgenda, hasMails: hasMails, hasInspiration: hasInspiration,
                                       hasMeetings: hasMeetings, hasDictation: hasDictation)
            .compactMap { section in allCases.first { $0.section == section } }
            .filter { $0 != .colin || (hasMails && hasColin) }
        return [[.addOns], work + (hasPhone ? [.iphone] : []), hubPanes(hasAgenda: hasAgenda)]
    }

    /// The section of the sidebar a family is about (lot 7, 19/11): Colin's is the Accueil, where he lives.
    var section: SidebarItem? {
        switch self {
        case .colin: .home
        case .projects: .projects
        case .meetings: .meetings
        case .calendar: .calendar
        case .mails: .mails
        case .inspiration: .inspiration
        case .dictation: .dictation
        case .vigie: .vigie
        case .addOns, .general, .accounts, .iphone, .diagnostic, .journal: nil
        }
    }

    /// The pages a family opens from a line of its own: Général, the Journal (the Diagnostic is a family since 21/11).
    var lines: [SettingsPane] {
        self == .general ? [.journal] : []
    }

    /// The family whose line opens this page; nil for a family.
    var parent: SettingsPane? {
        SettingsPane.allCases.first { $0.lines.contains(self) }
    }
}

/// Where the window is: the app sets it to open a meeting from the menu.
@MainActor
public final class WindowRouter: ObservableObject {
    @Published public var section: SidebarItem = .projects { didSet { moved() } }
    @Published public var selection: UUID? { didSet { moved() } }
    /// A moment to play in the selected meeting, asked by the search.
    @Published public var seekRequest: (meetingID: UUID, seconds: Double)?
    @Published public var query = ""
    /// The family of Réglages entered; `nil` for the list of families.
    @Published public var settingsPane: SettingsPane? { didSet { moved() } }
    @Published public var contactSelection: UUID? { didSet { moved() } }
    /// An event Accueil asked Calendrier to open (14/11).
    @Published public var eventSelection: String?
    /// A project Accueil asked Projets to open (review of 14/11).
    @Published public var projectSelection: UUID?
    /// The thread open in Mails (`account|threadID`); `nil` for the list (14/11).
    @Published public var mailSelection: String? { didSet { moved() } }
    /// The thread open over the Accueil (18/11: « Relire », « Ouvrir »): its own, the one of Mails stays as it is.
    @Published public var homeMail: String? { didSet { moved() } }
    /// A new event asked for (« Coup d'œil », Calendrier's « + »): Calendrier opens its editor, then clears it. A new
    /// value per request, so that two requests in a row open two editors.
    @Published public var newEventRequest: UUID?
    /// The notifications' panel asked for: the sidebar's bell opens it once on screen, then clears it.
    @Published public var notificationsRequested = false
    /// The page of « Inspiration » shown (Websites, Branding, Mock-ups), and the item open over it (16/11).
    @Published public var inspirationPage: InspirationKind = .website { didSet { moved() } }
    @Published public var inspirationItem: UUID? { didSet { moved() } }
    /// ⌘N on a page whose « + » the router cannot reach itself (Inspiration's, lot 4, 19/11): the page adds once it is
    /// on screen, then clears it. A new value per request.
    @Published public var addRequest: UUID?

    public init() {}

    /// A place of the window, for what opens it from outside (« Coup d'œil », the notifications).
    public enum Place: Equatable, Sendable {
        case section(SidebarItem)
        case meeting(UUID)
        case event(String)
        /// A thread (`account|threadID`), or nil for the inbox's list.
        case mail(String?)
        /// A family of Réglages, or nil for the list of families.
        case settings(SettingsPane?)
        /// The notifications' panel, under the sidebar's bell.
        case notifications
        /// Calendrier, with the editor of a new event open.
        case newEvent
        /// A page of « Inspiration », and one of its items open (16/11).
        case inspiration(InspirationKind, item: UUID? = nil)
    }

    /// Goes there; the app then shows the window.
    public func go(to place: Place) {
        switch place {
        case .section(let item): section = item
        case .meeting(let id): open(meetingID: id, at: nil)
        case .event(let id): openEvent(id)
        case .mail(let key): openMail(key)
        case .settings(let pane): openSettings(pane)
        case .notifications: openNotifications()
        case .newEvent: newEvent()
        case .inspiration(let kind, let item): openInspiration(kind, item: item)
        }
    }

    /// A page of « Inspiration », from its grid or on one of its items.
    public func openInspiration(_ kind: InspirationKind, item: UUID? = nil) {
        section = .inspiration
        inspirationPage = kind
        inspirationItem = item
    }

    /// Calendrier, its editor open on a new event.
    public func newEvent() {
        section = .calendar
        newEventRequest = UUID()
    }

    /// The notifications' panel, under the sidebar's bell (the page shown stays).
    public func openNotifications() {
        notificationsRequested = true
    }

    public func openContact(_ id: UUID) {
        section = .contacts
        contactSelection = id
    }

    public func openProject(_ id: UUID) {
        section = .projects
        // In the same turn as the section, where the app keeps the open project (lot 4, 19/11): one step, which « Fermer »
        // goes back from, to where the project was opened. Without it, Projets opens it once on screen.
        if let restoreProject { restoreProject(id) } else { projectSelection = id }
    }

    public func openEvent(_ id: String) {
        section = .calendar
        eventSelection = id
    }

    public func openMail(_ threadKey: String?) {
        section = .mails
        mailSelection = threadKey
    }

    /// The menu's « Diagnostic… », the first launch and the alerts.
    public func openDiagnostic() {
        openSettings(.diagnostic)
    }

    public func openSettings(_ pane: SettingsPane?) {
        section = .settings
        settingsPane = pane
    }

    public func open(meetingID: UUID, at seconds: Double?) {
        section = .meetings
        selection = meetingID
        seekRequest = seconds.map { (meetingID, $0) }
    }

    // MARK: - « Précédent », « Suivant »

    /// Where the window is, for « Précédent » and « Suivant » (Paul, 16/11: « je fais retour sur les pages internet,
    /// sur n'importe quoi »): the section and what is open in it. The open project and the mails' folder are kept by
    /// their libraries, which tell the router (`projectChanged`, `mailFolderChanged`) and are asked them back.
    struct Location: Equatable {
        var section: SidebarItem
        var meeting: UUID?
        var mail: String?
        var mailFolder: MailFolder
        var settingsPane: SettingsPane?
        var contact: UUID?
        var project: UUID?
        var inspirationPage: InspirationKind
        var inspirationItem: UUID?
        var homeMail: String?
    }

    /// The steps kept behind: a long morning of clicks.
    static let depth = 100

    public var restoreProject: ((UUID?) -> Void)?
    public var restoreMailFolder: ((MailFolder) -> Void)?
    private var project: UUID?
    private var mailFolder: MailFolder = .inbox
    private var back: [Location] = []
    private var forward: [Location] = []
    /// The place the window is at, as last settled; at first, the router's own defaults.
    private var current = Location(section: .projects, meeting: nil, mail: nil, mailFolder: .inbox, settingsPane: nil, contact: nil,
                                   project: nil, inspirationPage: .website, inspirationItem: nil)
    private var restoring = false
    private var pending = false

    public var canGoBack: Bool { !back.isEmpty || (pending && location != current) }
    public var canGoForward: Bool { !forward.isEmpty }

    var location: Location {
        Location(section: section, meeting: selection, mail: mailSelection, mailFolder: mailFolder, settingsPane: settingsPane,
                 contact: contactSelection, project: project, inspirationPage: inspirationPage, inspirationItem: inspirationItem, homeMail: homeMail)
    }

    /// Projets opened a project, or went back to the grid.
    public func projectChanged(_ id: UUID?) {
        guard project != id else { return }
        project = id
        moved()
    }

    /// Mails showed another folder.
    public func mailFolderChanged(_ folder: MailFolder) {
        guard mailFolder != folder else { return }
        mailFolder = folder
        moved()
    }

    /// The changes of one gesture (a section and what opens in it) make one step: kept at the end of the turn.
    private func moved() {
        guard !restoring, !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in self?.settle() }
    }

    /// The place reached becomes a step; what was ahead goes. A list choosing its first row by itself only refines
    /// the place.
    func settle() {
        pending = false
        let now = location
        guard now != current else { return }
        if Self.refines(now, current) {
            current = now
            return
        }
        back.append(current)
        if back.count > Self.depth { back.removeFirst(back.count - Self.depth) }
        forward.removeAll()
        current = now
    }

    /// The meetings' and the contacts' lists choose a row when none is: the same place, refined.
    static func refines(_ now: Location, _ before: Location) -> Bool {
        var filled = before
        if before.meeting == nil { filled.meeting = now.meeting }
        if before.contact == nil { filled.contact = now.contact }
        return filled == now
    }

    /// The window opens: where it is now is the start, nothing behind (the launch's « Accueil » is no step back).
    public func clearHistory() {
        pending = false
        back.removeAll()
        forward.removeAll()
        current = location
    }

    /// The mouse's « Précédent », ⌘[, the trackpad's swipe to the right.
    public func goBack() {
        settle()
        guard let previous = back.popLast() else { return }
        forward.append(current)
        restore(previous)
    }

    /// The mouse's « Suivant », ⌘], the swipe to the left.
    public func goForward() {
        settle()
        guard let next = forward.popLast() else { return }
        back.append(current)
        restore(next)
    }

    // MARK: - « Fermer, c'est revenir » (lot 4, 19/11)

    /// What is open over a section's root, the one thing « Fermer » closes there.
    enum Opened: Equatable {
        case homeMail, mail, project, inspirationItem, settingsPane
    }

    static func opened(_ place: Location) -> Opened? {
        switch place.section {
        case .home: place.homeMail != nil ? .homeMail : nil
        case .mails: place.mail != nil ? .mail : nil
        case .projects: place.project != nil ? .project : nil
        case .inspiration: place.inspirationItem != nil ? .inspirationItem : nil
        case .settings: place.settingsPane != nil ? .settingsPane : nil
        case .meetings, .calendar, .contacts, .dictation, .vigie: nil
        }
    }

    /// The steps behind, the gesture under way counted as one (as `settle` will keep it).
    private var stepsBehind: [Location] {
        let now = location
        guard pending, now != current, !Self.refines(now, current) else { return back }
        return back + [current]
    }

    /// How many steps « Fermer » goes back: past the neighbours browsed in the same section (a thread, then the next
    /// one), to the place the object was opened from. Nil when it was open from the start (nothing behind it).
    private func stepsToClose() -> Int? {
        let now = location
        guard let opened = Self.opened(now) else { return nil }
        let behind = stepsBehind
        let browsed = behind.reversed().prefix { $0.section == now.section && Self.opened($0) == opened }.count
        return browsed < behind.count ? browsed + 1 : nil
    }

    /// ✕, Échap, a click beside a panel, the ‹ of a page (lot 4, 19/11: « Fermer, c'est revenir »): back where the
    /// object was opened from, another section included, without a step of its own. Ten threads read are no twenty steps,
    /// and « Suivant » opens the object again. Opened first thing (the window came up on it), it closes in place.
    /// False when nothing is open: the page closes what it shows itself.
    @discardableResult
    public func close() -> Bool {
        guard Self.opened(location) != nil else { return false }
        if let steps = stepsToClose() {
            for _ in 0..<steps { goBack() }
            return true
        }
        settle()
        restoring = true
        switch Self.opened(location) {
        case .homeMail?: homeMail = nil
        case .mail?: mailSelection = nil
        case .project?:
            project = nil
            restoreProject?(nil)
        case .inspirationItem?: inspirationItem = nil
        case .settingsPane?: settingsPane = nil
        case nil: break
        }
        restoring = false
        current = location
        pending = false
        return true
    }

    /// The help of a way back: where « Fermer » leads (« Revenir à l'Accueil (Échap) »), written by `Words.help` (lot 10,
    /// 20/11).
    public var returnHelp: String {
        let now = location
        guard Self.opened(now) != nil else { return Words.help("Fermer", .escape) }
        let behind = stepsBehind
        let destination = stepsToClose().map { behind[behind.count - $0] }?.section ?? now.section
        return Words.help("Revenir à \(destination == .home ? "l'Accueil" : destination.title)", .escape)
    }

    private func restore(_ place: Location) {
        restoring = true
        defer { restoring = false }
        section = place.section
        selection = place.meeting
        mailSelection = place.mail
        homeMail = place.homeMail
        settingsPane = place.settingsPane
        contactSelection = place.contact
        inspirationPage = place.inspirationPage
        inspirationItem = place.inspirationItem
        project = place.project
        restoreProject?(place.project)
        mailFolder = place.mailFolder
        restoreMailFolder?(place.mailFolder)
        current = place
        pending = false
    }
}

/// What goes back and what goes forward (Paul, 16/11): the mouse's side buttons, ⌘[ and ⌘] (by where they are on the
/// keyboard, as Safari, whatever its layout), ⌘← and ⌘→ outside a text being written, the trackpad's swipe. And the
/// window's keys (lot 4, 19/11): ⌘1 to ⌘9 for the sidebar's rows, ⌘, for Réglages, ⌘N for the page's « + », ⌘F for its
/// search. The app has no menu bar of its own (an agent): its key monitor reads them here.
public enum NavigationInput {
    public enum Direction: Equatable, Sendable { case back, forward }

    /// What a key, a button or a swipe asks of the window.
    public enum Command: Equatable, Sendable {
        case back, forward
        /// The sidebar's row of that number, from 1.
        case section(Int)
        case settings
        /// The page's « + ».
        case new
        /// The page's search field.
        case search
    }

    public enum Gesture: Equatable {
        case mouse(button: Int)
        /// `characters`: what the key writes without its modifiers (Shift aside), for the keys read by their letter.
        case key(code: UInt16, modifiers: NSEvent.ModifierFlags, editingText: Bool, characters: String = "")
        case swipe(deltaX: CGFloat)
    }

    static let leftBracket: UInt16 = 33, rightBracket: UInt16 = 30, leftArrow: UInt16 = 123, rightArrow: UInt16 = 124

    /// The digits' keys by where they are, the top row then the keypad: on an AZERTY keyboard, ⌘1 is the « & » key, as
    /// in every app of the Mac.
    static let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
                                        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9]

    public static func direction(_ gesture: Gesture) -> Direction? {
        switch command(gesture) {
        case .back?: .back
        case .forward?: .forward
        default: nil
        }
    }

    /// None of these keys is a text's: ⌘1, ⌘, ⌘N and ⌘F work while writing; ⌘← and ⌘→ stay the text's (its line's
    /// start and end).
    public static func command(_ gesture: Gesture) -> Command? {
        switch gesture {
        case .mouse(let button):
            return button == 3 ? .back : button == 4 ? .forward : nil
        case .key(let code, let modifiers, let editingText, let characters):
            guard modifiers.intersection([.command, .option, .control, .shift]) == .command else { return nil }
            switch code {
            case leftBracket: return .back
            case rightBracket: return .forward
            case leftArrow: return editingText ? nil : .back
            case rightArrow: return editingText ? nil : .forward
            default: break
            }
            if let digit = digits[code] { return .section(digit) }
            switch characters.lowercased() {
            case ",": return .settings
            case "n": return .new
            case "f": return .search
            default: return nil
            }
        case .swipe(let deltaX):
            return deltaX > 0 ? .back : deltaX < 0 ? .forward : nil
        }
    }

    /// An event of the window, read.
    public static func command(of event: NSEvent, editingText: Bool) -> Command? {
        switch event.type {
        case .otherMouseDown: command(.mouse(button: event.buttonNumber))
        case .keyDown:
            command(.key(code: event.keyCode, modifiers: event.modifierFlags, editingText: editingText,
                         characters: event.charactersIgnoringModifiers ?? ""))
        case .swipe: command(.swipe(deltaX: event.deltaX))
        default: nil
        }
    }

    public static func direction(of event: NSEvent, editingText: Bool) -> Direction? {
        switch command(of: event, editingText: editingText) {
        case .back?: .back
        case .forward?: .forward
        default: nil
        }
    }

    /// Whether Paul is writing where the keyboard is (lot 4, 19/11): a text view (the editor of a field too), or a
    /// mail's editor, a page made to be written in. ⌘← went back a page there instead of to the line's start. A mail
    /// read is a page too, but not written in: the keys still go back and forth over it.
    public static func isEditing(_ responder: NSResponder?) -> Bool {
        if responder is NSTextView { return true }
        var view = responder as? NSView
        while let current = view {
            if current is RichTextEditor.EditorWebView { return true }
            view = current.superview
        }
        return false
    }
}

/// hub's window: the projects, the meetings, and Réglages (updates, diagnostic, journal).
public struct MainWindowView<Diagnostic: View>: View {
    /// The sidebar, the meetings' list, its divider and the smallest meeting page: derived from them, so that the
    /// narrowest window never squeezes the sidebar nor cuts the page (correctifs, 15/11: 860 had become too narrow).
    public static var minimumWidth: CGFloat { sidebarWidth + meetingListWidth + 1 + meetingPageMinimumWidth }
    /// Fixed (Paul, 15/11): one width, whatever the section. 224 since the folders went under « Plus » and the boxes
    /// into Mails (lot 4, 19/11: 252 took 28 % of a narrow window).
    static var sidebarWidth: CGFloat { 224 }
    /// The list of the meetings, fixed (13/11).
    static var meetingListWidth: CGFloat { 300 }
    /// A meeting's page, at its narrowest.
    static var meetingPageMinimumWidth: CGFloat { 360 }

    @ObservedObject var library: MeetingLibrary
    let projects: ProjectLibrary?
    let agenda: AgendaLibrary?
    let mails: MailLibrary?
    /// What the Accueil knows (18/11), kept by the app whether the window shows or not.
    let colin: ColinLibrary?
    /// Colin's thread and bar (18/11); none in a window made without it: nothing is ever launched from a capture.
    let thread: ColinThread?
    /// The probe of Colin, which keeps his account (17/11): Réglages › Colin chooses it too.
    let colinProbe: ColinProbeControl?
    /// The Claude accounts Vigie knows (0.36.0): the app's own; a window made without it never reads Vigie.
    let claudeAccounts: ClaudeAccountsModel?
    let inspiration: InspirationLibrary?
    let updates: UpdateService?
    let notifications: NotificationHub?
    let startup: StartupControl?
    /// Réglages › iPhone (20/11): the app's own; none in a window made without it.
    let phone: PhoneAccess?
    /// The add-ons installed (20/11): Réunions shows in the sidebar only with its own.
    let addOns: Set<AddOn>
    let addOnControl: AddOnControl?
    /// The Dictée, when installed (20/11).
    let dictation: DictationLibrary?
    let dictationService: DictationService?
    /// Vigie, when installed (21/11).
    let vigie: VigieLibrary?
    @ObservedObject var router: WindowRouter
    let paths: AppPaths
    let diagnostic: Diagnostic
    @State private var columns: NavigationSplitViewVisibility = .all

    public init(
        library: MeetingLibrary, projects: ProjectLibrary? = nil, agenda: AgendaLibrary? = nil, mails: MailLibrary? = nil, colin: ColinLibrary? = nil,
        thread: ColinThread? = nil, colinProbe: ColinProbeControl? = nil, claudeAccounts: ClaudeAccountsModel? = nil, inspiration: InspirationLibrary? = nil, updates: UpdateService? = nil, notifications: NotificationHub? = nil,
        startup: StartupControl? = nil, phone: PhoneAccess? = nil, addOns: Set<AddOn> = Set(AddOn.allCases), addOnControl: AddOnControl? = nil,
        dictation: DictationLibrary? = nil, dictationService: DictationService? = nil, vigie: VigieLibrary? = nil,
        router: WindowRouter, paths: AppPaths,
        @ViewBuilder diagnostic: () -> Diagnostic
    ) {
        self.phone = phone
        self.addOns = addOns
        self.addOnControl = addOnControl
        self.dictation = dictation
        self.dictationService = dictationService
        self.vigie = vigie
        self.notifications = notifications
        self.startup = startup
        self.library = library
        self.projects = projects
        self.agenda = agenda
        self.mails = mails
        // The app keeps its own; a window made without one (a capture, a test) gets one for its Accueil.
        // Only when Colin is installed (20/11).
        self.colin = colin ?? (addOns.contains(.colin) ? agenda.map { ColinLibrary(agenda: $0, mails: mails) } : nil)
        self.thread = thread
        self.colinProbe = colinProbe
        self.claudeAccounts = claudeAccounts
        self.inspiration = inspiration
        self.updates = updates
        self.router = router
        self.paths = paths
        self.diagnostic = diagnostic()
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(router: router, library: library, agenda: agenda, mails: mails,
                    items: SidebarItem.visible(hasProjects: projects != nil, hasAgenda: agenda != nil, hasMails: mails != nil,
                                               hasInspiration: inspiration != nil, hasMeetings: addOns.contains(.meetings),
                                               hasDictation: dictation != nil, hasVigie: vigie != nil),
                    footer: SidebarItem.footer(hasAgenda: agenda != nil), vigie: vigie)
                // One width, always: a sidebar free to resize changed size from one section to the next (Paul, 15/11).
                .navigationSplitViewColumnWidth(Self.sidebarWidth)
                // The window is made by hand: SwiftUI does not add this button there. It keeps a toolbar on every
                // page, so the window's buttons never move and nothing sticks to the top (Paul, 14/11).
                .toolbar {
                    ToolbarItem {
                        Button {
                            withAnimation(Motion.standard) { columns = columns == .detailOnly ? .all : .detailOnly }
                        } label: {
                            Label("Barre latérale", systemImage: "sidebar.left")
                        }
                        .help("Afficher ou masquer la barre latérale")
                    }
                    // The bell, up beside the sidebar's button, as Notion's inbox (lot 4, 19/11): no longer beside
                    // Réglages, two gestures on one row.
                    if let inbox = notifications?.inbox {
                        ToolbarItem {
                            NotificationBell(inbox: inbox, arrowEdge: .bottom, inToolbar: true, request: $router.notificationsRequested) {
                                router.perform($0, agenda: agenda, mails: mails)
                            }
                        }
                    }
                }
        } detail: {
            switch router.section {
            case .home:
                if let agenda, let colin { HomeView(agenda: agenda, mails: mails, colin: colin, thread: thread, router: router, accounts: claudeAccounts) }
            case .calendar:
                if let agenda { CalendarView(agenda: agenda, router: router) }
            case .contacts:
                if let agenda { ContactsView(agenda: agenda, router: router) }
            case .mails:
                if let mails { MailSectionView(mails: mails, router: router) }
            case .inspiration:
                if let inspiration { InspirationSectionView(library: inspiration, router: router) }
            case .dictation:
                if let dictation { DictationPage(library: dictation, service: dictationService) }
            case .vigie:
                if let vigie { VigiePage(library: vigie) }
            case .projects:
                if let projects {
                    ProjectsView(library: projects)
                        .onAppear {
                            projects.openMeeting = { [weak router] id in router?.open(meetingID: id, at: nil) }
                            projects.openMail = { [weak router] key in router?.openMail(key) }
                            projects.openContact = { [weak router] id in router?.openContact(id) }
                            // Lot 4, 19/11: its events lead to them; closing goes back where it was opened from.
                            projects.openEvent = { [weak router] id in router?.openEvent(id) }
                            projects.close = { [weak router] in router?.close() ?? false }
                            projects.returnHelp = { [weak router] in router?.returnHelp ?? Words.help("Revenir à Projets", .escape) }
                            openAskedProject(projects)
                        }
                        .onChange(of: router.projectSelection) { _, _ in openAskedProject(projects) }
                } else {
                    // What did not work, then what to do (lot 10, 20/11).
                    ContentUnavailableView("Les projets ne s'ouvrent pas", systemImage: "square.grid.3x2",
                                           description: Text("Quitte hub et rouvre-le."))
                }
            case .meetings:
                // A fixed list and a detail that wraps its text: a split view let the detail push the
                // window wider than the screen (13/11).
                HStack(spacing: 0) {
                    Group {
                        if SearchModel.shouldSearch(router.query) {
                            SearchResultsView(query: router.query, transcripts: library.transcripts) { id, seconds in
                                router.open(meetingID: id, at: seconds)
                            }
                        } else {
                            MeetingListView(library: library, selection: $router.selection, paths: paths, projects: projects?.projects ?? [])
                        }
                    }
                    .frame(width: Self.meetingListWidth)
                    // Neither column passes under the toolbar: each would draw its own box there (19/11).
                    .belowToolbar()
                    Divider()
                    Group {
                        if let id = router.selection, let row = library.row(id) {
                            MeetingDetailView(row: row, store: library.store, paths: paths, transcripts: library.transcripts,
                                              projects: projects?.projects ?? [],
                                              queue: library.queue, summaries: library.summaries, summaryUnavailable: library.summaryUnavailable,
                                              summaryProgress: library.summaryProgress[row.id], job: library.jobs[row.id], meetingActive: library.meetingActive,
                                              router: router, agenda: agenda)
                                .id(id)
                        } else {
                            ContentUnavailableView("Aucune réunion choisie", systemImage: "mic",
                                                   description: Text("Choisis une réunion dans la liste."))
                        }
                    }
                    .frame(minWidth: Self.meetingPageMinimumWidth, maxWidth: .infinity, maxHeight: .infinity)
                    .belowToolbar()
                }
                // The sidebar's word; never the meeting's title, written large in its page (lot 4, 19/11).
                .windowTitle("Réunions")
                // « réunion », what hub recorded; never « transcriptions » for the page (lot 10, 20/11).
                .searchable(text: $router.query, placement: .toolbar, prompt: "Chercher dans les réunions")
            case .settings:
                SettingsPage(router: router, updates: updates, projects: projects, agenda: agenda, mails: mails, inspiration: inspiration,
                             library: library, notifications: notifications, startup: startup, colinThread: thread, colinProbe: colinProbe,
                             phone: phone, addOns: addOns, addOnControl: addOnControl, dictationService: dictationService, vigie: vigie) {
                    diagnostic
                } journal: {
                    JournalView(entries: library.journal)
                }
            }
        }
        .frame(minWidth: Self.minimumWidth, minHeight: 520)
        // A project's name in a thread leads to it, from Mails as from the Accueil (lot 4, 19/11).
        .onAppear { mails?.router = router }
        // hub's own accent, ink, whatever the Mac's (design system v2, 19/11): the app sets it on the window's root
        // too; here, a window made by a test or a capture shows it as well.
        .tint(Tint.control.color)
    }

    private func openAskedProject(_ projects: ProjectLibrary) {
        guard let id = router.projectSelection else { return }
        router.projectSelection = nil
        projects.selected = id

    }
}

/// The meetings by day, newest first: the newest opens by itself, a right click gives the usual gestures (15/11).
struct MeetingListView: View {
    @ObservedObject var library: MeetingLibrary
    @Binding var selection: UUID?
    var paths: AppPaths?
    var projects: [ProjectRow] = []
    @State private var deleting: MeetingRow?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let sections = MeetingListModel.sections(library.rows, now: context.date, calendar: .current)
            if sections.isEmpty {
                // « visio », never « un Meet »; a sentence with its « : », French typography (lot 10, 20/11).
                ContentUnavailableView("Aucune réunion", systemImage: "mic",
                                       description: Text(Words.typeset("Rejoins une visio dans Dia : elle s'enregistre toute seule.")))
            } else {
                List(selection: $selection) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.rows) { row in
                                MeetingRowView(row: row, now: context.date, badge: TranscriptModel.badge(library.jobs[row.id]),
                                               project: projectName(row),
                                               summary: MeetingListModel.summaryLine(overview: library.overviews[row.id], job: library.summaryJobs[row.id]))
                                    .tag(row.id)
                                    .contextMenu { menu(row) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { openNewest() }
        .onChange(of: library.rows) { previous, _ in openNewest(previous: previous) }
        .confirmationDialog("Supprimer « \(deleting?.title ?? "") » ?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { row in
            Button("Supprimer", role: .destructive) { delete(row) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("L'audio va à la Corbeille, d'où tu peux encore le récupérer.")
        }
    }

    private func projectName(_ row: MeetingRow) -> String? {
        row.projectID.flatMap { id in projects.first { $0.id == id }?.name }
    }

    /// Nothing chosen: the newest opens. The meeting chosen went to the Trash: its neighbour, from its page as from
    /// the list. One older than the list stays (correctifs, 15/11).
    private func openNewest(previous: [MeetingRow] = []) {
        let open = MeetingListModel.meetingToOpen(selection: selection, rows: library.rows, previous: previous, isGone: library.isGone)
        if open != selection { selection = open }
    }

    @ViewBuilder
    private func menu(_ row: MeetingRow) -> some View {
        Button("Ouvrir") { selection = row.id }
        Button("Refaire le compte rendu") {
            let summaries = library.summaries, id = row.id
            Task { await summaries?.redo(meetingID: id) }
        }
        .disabled(library.summaries == nil || row.source == .imported || row.status.isUnfinished || row.transcribedAt == nil
                  || library.summaryJobs[row.id]?.state == .running)
        if let paths {
            Divider()
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([paths.meetingFolder(row.id)]) }
                .disabled(row.source == .imported)
            Button("Supprimer…", role: .destructive) { deleting = row }
                .disabled(row.status.isUnfinished)
        }
    }

    private func delete(_ row: MeetingRow) {
        guard let paths else { return }
        if selection == row.id { selection = MeetingListModel.neighbor(of: row.id, in: library.rows) }
        library.moveToTrash(row, folder: paths.meetingFolder(row.id))
    }
}

/// One meeting: its title, when and how long (and its project), then its summary's first lines (15/11).
struct MeetingRowView: View {
    let row: MeetingRow
    let now: Date
    var badge: TranscriptBadge?
    var project: String?
    var summary: MeetingListModel.SummaryLine?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(row.title).font(.rowTitle.weight(.medium)).lineLimit(1)
                Spacer(minLength: Space.xs)
                chips
            }
            Text(MeetingListModel.metaText(row, project: project, now: now))
                .font(.meta.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let summary {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: summary.kind == .failed ? "exclamationmark.triangle" : "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        // A summary that failed: the icon of attention, its sentence grey as the others, never an
                        // orange sentence; the sparkles, a decoration, grey (design system v2, 19/11).
                        .foregroundStyle(summary.kind == .failed ? Tint.attention : Color.secondary)
                        .symbolEffect(.pulse, isActive: summary.kind == .writing)
                    Text(summary.text)
                        .font(.rowBody)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverRow(inset: Space.s)
    }

    @ViewBuilder
    private var chips: some View {
        // A meeting that records: the red of the recording; one interrupted, failed or to check: the color of attention
        // (design system v2, 19/11).
        if row.status.isUnfinished {
            Chip("En cours", systemImage: "record.circle", tint: Tint.recording)
        } else if row.status == .interrupted {
            Chip("Interrompue", tint: Tint.attention)
        }
        if let badge, !row.status.isUnfinished {
            // The state says the color, never the words (lot 10, 20/11).
            Chip(badge.text, tint: badge.needsAttention ? Tint.attention : nil)
        }
    }
}
