import Mail
import Persistence
import PolhubDesign
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

extension MailText {
    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// « 8:00 », « 13:30 ».
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return "\(parts.hour ?? 0):" + String(format: "%02d", parts.minute ?? 0)
    }

    /// When a programmed mail leaves: « aujourd'hui 18:30 », « demain 8:00 », « lundi 8:00 » within the week,
    /// « lundi 24 novembre 8:00 » beyond; « hier 8:00 » for one late.
    static func scheduled(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let time = clock(date, calendar: calendar)
        switch days {
        case 0: return "aujourd'hui \(time)"
        case 1: return "demain \(time)"
        case -1: return "hier \(time)"
        case -6...6: return "\(format(date, "EEEE", calendar: calendar)) \(time)"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return "\(format(date, sameYear ? "EEEE d MMMM" : "EEEE d MMMM y", calendar: calendar)) \(time)"
        }
    }

    /// The same, short, at the end of a line: « 18:30 », « demain 8:00 », « lun. 8:00 », « 24 nov. 8:00 ».
    static func scheduledShort(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let time = clock(date, calendar: calendar)
        switch days {
        case 0: return time
        case 1: return "demain \(time)"
        case -1: return "hier \(time)"
        case -6...6: return "\(format(date, "EEE", calendar: calendar)) \(time)"
        default: return "\(format(date, "d MMM", calendar: calendar)) \(time)"
        }
    }

    /// Under a choice of the menu: « sam. 21 nov. 8:00 ».
    static func presetDate(_ date: Date, calendar: Calendar = .current) -> String {
        "\(format(date, "EEE d MMM", calendar: calendar)) \(clock(date, calendar: calendar))"
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
        .buttonStyle(.glassProminent)
        .fixedSize()
        .help("Programmer l'envoi")
    }
}

/// « Choisir une date et une heure… »: the day on a calendar, the hour beside; five minutes from now at least.
struct SchedulePicker: View {
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
            Text("Ton Mac doit être allumé et Polhub ouvert à cette heure-là. Sinon, le mail part à ton retour, ou attend ton accord après 12 h de retard.")
                .font(.meta).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.m) {
                Spacer(minLength: 0)
                Button("Annuler") { done(nil) }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("Programmer l'envoi") { done(max(date, earliest)) }
                    .buttonStyle(.glassProminent)
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
        // Only the icon carries a color, on a neutral band (design system v2, 19/11): grey while the mail waits for its
        // time (it is told, not called); the late's red once it waits for Paul, as « En retard » in the bar and the list.
        let tint = held ? Tint.late : Color.secondary
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.m) {
                Image(systemName: held ? "exclamationmark.circle.fill" : "clock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(held ? "Pas encore parti : programmé pour \(MailText.scheduled(entry.sendAt))" : "Programmé pour \(MailText.scheduled(entry.sendAt))")
                        .font(.rowBody.weight(.semibold))
                    Text(held ? "\(MailLibrary.lateReason(entry).prefix(1).uppercased() + MailLibrary.lateReason(entry).dropFirst()) : il attend ton accord."
                         : entry.state == .leaving ? "Envoi en cours…" : "Il ne se modifie plus. Changé dans Gmail ou sur ton téléphone, il ne partira pas.")
                        .font(.meta).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if entry.state == .leaving {
                    ProgressView().controlSize(.small)
                } else if !held {
                    cancel
                }
            }
            if held {
                HStack(spacing: Space.m) {
                    // The screen's principal action, in the content: full and matte (design system v2, 19/11).
                    Button("Envoyer maintenant") { mails.sendScheduledNow(draftID) }
                        .buttonStyle(.primary)
                        .disabled(mails.sending != nil)
                        .help("Il part dans quelques secondes, que tu peux encore annuler")
                    cancel
                }
                .padding(.leading, 22 + Space.m)
            }
        }
        .padding(Space.m)
        .background(Surface.raised, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var cancel: some View {
        Button("Annuler l'envoi programmé") { mails.unschedule(draftID) }
            .buttonStyle(.secondary)
            .help("Le mail redevient un brouillon, que tu peux modifier")
    }
}

/// « Programmés »: the mails that wait for their time, the next first, on the drafts' lines, with their hour in
/// place of the date. A click opens one; the pointer shows « Annuler l'envoi programmé » over the hour.
struct MailScheduledListView: View {
    @ObservedObject var mails: MailLibrary
    @ObservedObject var router: WindowRouter

    var body: some View {
        let waiting = mails.scheduledDrafts
        VStack(spacing: 0) {
            MailSearchLine(text: "Ton Mac doit être allumé et Polhub ouvert à l'heure prévue ; sinon le mail part à ton retour, ou attend ton accord après 12 h de retard.",
                           searching: false, icon: "clock")
            if waiting.isEmpty {
                ContentUnavailableView("Aucun envoi programmé", systemImage: "clock",
                                       description: Text("Un mail programmé attend ici son heure, puis part tout seul."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(waiting, id: \.draft.id) { item in
                            MailScheduledLine(draft: item.draft, entry: item.entry, color: mails.color(for: item.draft.account),
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
/// to whom, the subject and the start of the text, then when it leaves. On hover, its gestures cover the hour,
/// on the line's own ground: nothing moves.
struct MailScheduledLine: View {
    let draft: MailDraftRow
    let entry: ScheduledSend
    let color: Color
    let open: () -> Void
    let cancel: () -> Void
    var sendNow: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let held = entry.state == .held
        let people = draft.to.map { $0.name ?? $0.email }
        HStack(spacing: 0) {
            Capsule().fill(color).frame(width: 3, height: 22).padding(.leading, Space.m).help(draft.account)
            // Late: the late's red, on the icon, the word and the hour (design system v2, 19/11).
            Image(systemName: held ? "exclamationmark.circle" : "clock")
                .font(.system(size: 15))
                .foregroundStyle(held ? Tint.late : Color.secondary)
                .frame(width: 44)
            (Text(held ? "En retard" : "Programmé").foregroundStyle(held ? Tint.late : Color.secondary)
                + Text(people.isEmpty ? "" : " · \(people.joined(separator: ", "))"))
                .font(.rowTitle)
                .lineLimit(1)
                .frame(width: MailRow.sendersWidth, alignment: .leading)
                .padding(.trailing, Space.l)
            (Text(draft.subject.isEmpty ? "(sans objet)" : draft.subject).font(.rowTitle)
                + Text(draft.body.isEmpty ? "" : " — \(draft.body.replacingOccurrences(of: "\n", with: " "))").font(.rowBody).foregroundStyle(.secondary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(MailText.scheduledShort(entry.sendAt))
                .font(.meta.weight(.medium)).foregroundStyle(held ? Tint.late : Color.primary).monospacedDigit().lineLimit(1)
                .frame(minWidth: 58, alignment: .trailing)
                .help("Part \(MailText.scheduled(entry.sendAt))")
        }
        .overlay(alignment: .trailing) {
            if hovering, entry.state != .leaving {
                HStack(spacing: 2) {
                    if let sendNow { IconButton("paperplane", help: "Envoyer maintenant", action: sendNow) }
                    IconButton("xmark.circle", help: "Annuler l'envoi programmé", action: cancel)
                }
                .padding(.leading, Space.xxl)
                .background(LinearGradient(stops: [.init(color: MailSurface.unread.opacity(0), location: 0), .init(color: MailSurface.unread, location: 0.3)],
                                           startPoint: .leading, endPoint: .trailing))
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, Space.m)
        .padding(.trailing, Space.l)
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
