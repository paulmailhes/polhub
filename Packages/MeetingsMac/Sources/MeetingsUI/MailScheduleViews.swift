import Mail
import Persistence
import HubDesign
import SwiftUI

/// « Programmer l'envoi » (wave B, Paul's yes of 15/11): Gmail's choices next to « Envoyer », the date picker, the
/// banner of a programmed mail, and the folder « Programmés ».

/// One of Gmail's ready choices.
struct SchedulePreset: Identifiable, Equatable {
    let title: String
    let date: Date
    var id: String { title }
}

enum SchedulePresets {
    /// As Gmail: « Demain matin » 8:00, « Demain après-midi » 13:00, « Lundi matin » 8:00 (not on a Monday, nor on
    /// a Sunday, when it is tomorrow morning). In local time, whatever the change of hour.
    static func options(now: Date, calendar: Calendar = .current) -> [SchedulePreset] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        var options: [SchedulePreset] = []
        if let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) { options.append(SchedulePreset(title: "Demain matin", date: morning)) }
        if let afternoon = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: tomorrow) {
            options.append(SchedulePreset(title: "Demain après-midi", date: afternoon))
        }
        let weekday = calendar.component(.weekday, from: now)
        if weekday != 2, weekday != 1,
           let monday = calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime) {
            options.append(SchedulePreset(title: "Lundi matin", date: monday))
        }
        return options
    }

    /// The earliest choice by hand: five minutes from now.
    static let margin: TimeInterval = 5 * 60
}

/// The hours and the days of a programmed mail, by `Words` (lot 10, 20/11): the formatter of the system and the hours
/// made by hand are gone.
extension MailText {
    /// « 8:00 », « 13:30 ».
    static func clock(_ date: Date, calendar: Calendar = Words.calendar) -> String {
        Words.time(date, calendar: calendar)
    }

    /// When a programmed mail leaves, in a sentence: « aujourd'hui 18:30 », « demain 8:00 », « lundi 8:00 » within the
    /// week, « mardi 1er décembre à 8:00 » beyond; « hier 8:00 » for one late (`Words.moment`).
    static func scheduled(_ date: Date, now: Date = Date(), calendar: Calendar = Words.calendar) -> String {
        Words.moment(date, now: now, calendar: calendar)
    }

    /// The same, short, at the end of a line: « 18:30 », « demain 8:00 », « lun. 8:00 », « 1er déc. 8:00 »
    /// (`Words.shortMoment`).
    static func scheduledShort(_ date: Date, now: Date = Date(), calendar: Calendar = Words.calendar) -> String {
        Words.shortMoment(date, now: now, calendar: calendar)
    }

    /// Under a choice of the menu: « sam. 21 nov. 8:00 ».
    static func presetDate(_ date: Date, calendar: Calendar = Words.calendar) -> String {
        "\(Words.weekday(date, short: true, calendar: calendar)) \(Words.shortDate(date, now: date, calendar: calendar)) \(Words.time(date, calendar: calendar))"
    }
}

/// The arrow next to « Envoyer »: Gmail's choices, then « Choisir une date et une heure… ». One prominent glass
/// control with the button (`GlassEffectContainer`).
struct ScheduleMenu: View {
    let pick: (Date) -> Void
    let choose: () -> Void

    var body: some View {
        Menu {
            Section("Programmer l'envoi") {
                ForEach(SchedulePresets.options(now: Date())) { preset in
                    Button { pick(preset.date) } label: {
                        Text(preset.title)
                        Text(MailText.presetDate(preset.date))
                    }
                }
            }
            Divider()
            Button("Choisir une date et une heure…", action: choose)
        } label: {
            Image(systemName: "chevron.down").fontWeight(.semibold).accessibilityLabel("Programmer l'envoi")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.primary)
        .fixedSize()
        .help("Programmer l'envoi")
    }
}

/// « Choisir une date et une heure… »: the day on a calendar, the hour beside; five minutes from now at least.
struct SchedulePicker: View {
    /// What a programmed mail needs, written once: under the picker and over « Programmés » (lot 10, 20/11).
    static let note = "Le Mac doit être allumé et Polhub ouvert à l'heure prévue. Sinon le mail part à ton retour."

    @State private var date: Date
    private let earliest: Date
    let done: (Date?) -> Void

    init(now: Date = Date(), done: @escaping (Date?) -> Void) {
        let earliest = now.addingTimeInterval(SchedulePresets.margin)
        let tomorrow = SchedulePresets.options(now: now).first?.date ?? earliest
        self.earliest = earliest
        _date = State(initialValue: max(tomorrow, earliest))
        self.done = done
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Programmer l'envoi").font(.headline)
            DatePicker("Jour", selection: $date, in: earliest..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            HStack(spacing: Space.s) {
                Text("Heure").foregroundStyle(.secondary)
                DatePicker("Heure", selection: $date, in: earliest..., displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                Spacer(minLength: 0)
                Text(MailText.scheduled(date)).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.rowBody)
            Text(Self.note)
                .font(.meta).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                Spacer(minLength: 0)
                Button("Annuler") { done(nil) }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Programmer l'envoi") { done(max(date, earliest)) }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(Space.xl)
        .frame(width: 320)
    }
}

/// Above a programmed mail in the composer: when it leaves, and the way back; it is locked meanwhile. One that
/// waits for Paul (too late) says so, with the late's red, and « Envoyer maintenant ».
struct ScheduledBanner: View {
    let entry: ScheduledSend
    let draftID: String
    @ObservedObject var mails: MailLibrary

    var body: some View {
        let held = entry.state == .held
        // The mails' one band (lot 6, 19/11): only the icon carries a color — grey while the mail waits for its time (it
        // is told, not called), the late's red once it waits for Paul, as « En retard » in the bar and the list.
        Banner(held ? .late : .information,
               held ? "Pas encore parti : programmé pour \(MailText.scheduled(entry.sendAt))" : "Programmé pour \(MailText.scheduled(entry.sendAt))",
               // The capital by `Words` (lot 10, 20/11).
               detail: held ? "\(Words.capitalizedFirst(MailLibrary.lateReason(entry))) : il attend ton accord."
                   : entry.state == .leaving ? "Envoi en cours…" : "Il ne se modifie plus. Changé dans Gmail ou sur ton téléphone, il ne partira pas.",
               systemImage: held ? "exclamationmark.circle.fill" : "clock.fill") {
            if entry.state == .leaving {
                ProgressView().controlSize(.small)
            } else if held {
                // The screen's principal action, in the content: full and matte (design system v2, 19/11).
                Button("Envoyer maintenant") { mails.sendScheduledNow(draftID) }
                    .buttonStyle(.primary)
                    .disabled(mails.sending != nil)
                    // « Verbe + objet : conséquence » (lot 10, 20/11).
                    .help(Words.help("Envoyer maintenant", detail: "quelques secondes pour annuler"))
                cancel
            } else {
                cancel
            }
        }
    }

    private var cancel: some View {
        Button("Annuler l'envoi programmé") { mails.unschedule(draftID) }
            .buttonStyle(.secondary)
            // « Verbe + objet : conséquence » (lot 10, 20/11).
            .help(Words.help("Annuler l'envoi programmé", detail: "le mail redevient un brouillon"))
    }
}

/// « Programmés »: the mails that wait for their time, the next first, on the drafts' lines and the list's grid (lot 6,
/// 19/11), with their hour in place of the date. A click opens one; the pointer shows « Annuler l'envoi programmé » in
/// the hour's place.
struct MailScheduledListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter
    @AppStorage(Preferences.Key.mailDensity) private var density = MailDensity.defaut.rawValue

    var body: some View {
        let waiting = mails.scheduledDrafts
        let density = MailDensity(rawValue: density) ?? .defaut
        let stripes = MailGrid.showsStripes(accounts: mails.accounts.map(\.email), hidden: mails.hidden)
        VStack(spacing: 0) {
            // The same sentence as under the picker, written once (lot 10, 20/11).
            MailSearchLine(text: SchedulePicker.note, searching: false, icon: "clock")
            if waiting.isEmpty {
                MailEmptyView(state: mails.emptyState, mails: mails)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(waiting, id: \.draft.id) { item in
                            MailScheduledLine(draft: item.draft, entry: item.entry, color: stripes ? mails.color(for: item.draft.account) : nil,
                                              density: density,
                                              open: { mails.open(item.draft, router: router) },
                                              cancel: { mails.unschedule(item.draft.id) },
                                              // While another mail is in its delay, « Envoyer maintenant » waits (as the banner's).
                                              sendNow: item.entry.state == .held && mails.sending == nil ? { mails.sendScheduledNow(item.draft.id) } : nil)
                        }
                    }
                }
            }
        }
    }
}

/// A programmed mail on one line, as a draft's: « Programmé » (« En retard » in red when it waits for Paul) and
/// to whom, the subject and the start of the text, then when it leaves. Under the pointer, its gestures take the hour's
/// place in the end column, on the line's own ground: nothing moves, nothing covers the subject (lot 6, 19/11).
struct MailScheduledLine: View {
    let draft: MailDraftRow
    let entry: ScheduledSend
    /// The mailbox's stripe, when the list shows several.
    let color: Color?
    var density = MailDensity.defaut
    let open: () -> Void
    let cancel: () -> Void
    var sendNow: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let held = entry.state == .held
        let people = draft.to.map { $0.name ?? $0.email }
        let gestures = hovering && entry.state != .leaving
        MailGridLine(stripe: color, stripeHelp: draft.account) {
            // Late: the late's red, on the icon, the word and the hour (design system v2, 19/11).
            Image(systemName: held ? "exclamationmark.circle" : "clock")
                .font(.rowTitle)
                .foregroundStyle(held ? Tint.late : Color.secondary)
        } senders: {
            (Text(held ? "En retard" : "Programmé").foregroundStyle(held ? Tint.late : Color.secondary)
                + Text(people.isEmpty ? "" : " · \(people.joined(separator: ", "))"))
                .font(.rowTitle)
                .lineLimit(1)
        } subject: {
            // The screen's « (sans objet) » (lot 10, 20/11).
            (Text(draft.subject.isEmpty ? Words.noSubject : draft.subject).font(.rowTitle)
                + Text(draft.body.isEmpty ? "" : " — \(draft.body.replacingOccurrences(of: "\n", with: " "))").font(.rowBody).foregroundStyle(.secondary))
                .lineLimit(1)
        } end: {
            Text(MailText.scheduledShort(entry.sendAt))
                .font(.meta.weight(.medium)).foregroundStyle(held ? Tint.late : Color.primary).monospacedDigit().lineLimit(1)
                // An information, never a verb conjugated (lot 10, 20/11).
                .help("Départ \(MailText.scheduled(entry.sendAt))")
                .opacity(gestures ? 0 : 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    if gestures {
                        HStack(spacing: MailGrid.gestureSpacing) {
                            if let sendNow { IconButton("paperplane", help: "Envoyer maintenant", action: sendNow) }
                            IconButton("xmark.circle", help: "Annuler l'envoi programmé", action: cancel)
                        }
                    }
                }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, density.padding)
        .padding(.trailing, MailGrid.trailing)
        .background {
            Rectangle().fill(MailSurface.unread)
                .shadow(color: .black.opacity(hovering ? 0.2 : 0), radius: hovering ? 3 : 0, y: hovering ? 1 : 0)
        }
        .overlay(alignment: .bottom) { MailLine() }
        .zIndex(hovering ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .contextMenu {
            Button("Ouvrir", action: open)
            if let sendNow { Button("Envoyer maintenant", action: sendNow) }
            Button("Annuler l'envoi programmé", action: cancel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Annuler l'envoi programmé", cancel)
    }
}
