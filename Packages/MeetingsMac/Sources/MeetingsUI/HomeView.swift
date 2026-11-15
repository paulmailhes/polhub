import Agenda
import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI

/// What Accueil puts first (14/11).
enum HomeModel {
    /// The event under way, else the next one today; neither whole days nor declined ones.
    static func next(_ events: [CalendarEventRow], now: Date, calendar: Calendar = .current) -> CalendarEventRow? {
        events.filter { event in
            !event.allDay && event.endAt > now && calendar.isDate(event.startAt, inSameDayAs: now)
                && event.attendees.first(where: \.isSelf)?.response != "declined"
        }
        .min { $0.startAt < $1.startAt }
    }

    /// « en cours », « dans 12 min », « à 15:30 ».
    static func when(_ event: CalendarEventRow, now: Date) -> String {
        if event.startAt <= now { return "en cours" }
        let minutes = Int((event.startAt.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "dans \(minutes) min" }
        return "à " + event.startAt.formatted(date: .omitted, time: .shortened)
    }

    /// The cards of Accueil, in two columns that each stack their cards (15/11: a short card left a hole beside a
    /// long one): the day on the left, the work on the right; one column when the window is narrow.
    enum Part: CaseIterable {
        case today, meetings, urgent, unfiled
    }

    static let columns: [[Part]] = [[.today, .meetings], [.urgent, .unfiled]]
    static let single: [Part] = [.today, .urgent, .meetings, .unfiled]
}

/// Accueil: the next event to join, then today at a glance. Kept light on purpose: it will become a
/// conversation (Paul, 13/11).
struct HomeView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var library: MeetingLibrary
    @ObservedObject var router: WindowRouter

    /// A column of cards: two side by side from this width each, else one under the other.
    static let columnWidth: CGFloat = 320

    private var calendar: Calendar { CalendarView.calendar }
    private var today: [CalendarEventRow] {
        agenda.shown.filter { calendar.isDateInToday($0.startAt) || ($0.allDay && $0.startAt <= .now && $0.endAt > .now) }
            .sorted { ($0.allDay ? 0 : 1, $0.startAt) < ($1.allDay ? 0 : 1, $1.startAt) }
    }
    /// The most urgent projects: Priorité 2, in Paul's scale (15/11).
    private var urgent: [ProjectRow] { agenda.projects.filter { $0.status == .priorite2 } }
    /// Recent events with a recording but no project: one choice files the meeting and its guests.
    private var unfiled: [CalendarEventRow] {
        agenda.shown.filter { $0.projectID == nil && $0.meetingID != nil && $0.startAt > Date().addingTimeInterval(-14 * 86_400) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Page {
                PageHeader(Self.title(context.date), subtitle: summary)
                if let next = HomeModel.next(agenda.shown, now: context.date) {
                    NextEventCard(event: next, now: context.date, agenda: agenda, router: router)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Space.l) {
                        ForEach(HomeModel.columns, id: \.self) { cards in
                            VStack(alignment: .leading, spacing: Space.l) {
                                ForEach(cards, id: \.self) { card($0, now: context.date) }
                            }
                            .frame(minWidth: Self.columnWidth, idealWidth: Self.columnWidth, maxWidth: .infinity, alignment: .top)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.l) {
                        ForEach(HomeModel.single, id: \.self) { card($0, now: context.date) }
                    }
                }
            }
        }
        .windowTitle("Accueil")
    }

    @ViewBuilder
    private func card(_ card: HomeModel.Part, now: Date) -> some View {
        switch card {
        case .today: todayCard(now: now)
        case .meetings: meetingsCard
        case .urgent: urgentCard
        case .unfiled: unfiledCard
        }
    }

    static func title(_ date: Date) -> String {
        let text = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(CalendarView.locale))
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var summary: String {
        let count = today.filter { !$0.allDay }.count
        return count == 0 ? "Pas de rendez-vous aujourd'hui." : count == 1 ? "1 rendez-vous aujourd'hui." : "\(count) rendez-vous aujourd'hui."
    }

    private func projectName(_ id: UUID?) -> String? {
        id.flatMap { id in agenda.projects.first { $0.id == id }?.name }
    }

    // MARK: - Cards

    private func todayCard(now: Date) -> some View {
        HomeCard(title: "Aujourd'hui", systemImage: "calendar") {
            if today.isEmpty {
                EmptyLine(agenda.accounts.isEmpty ? "Connecte tes agendas dans Calendrier." : "Aucun rendez-vous.")
            }
            ShowMoreList(today, limit: 6) { event in
                let joinable = event.meetCode != nil && event.endAt > now && !event.allDay
                RowButton(action: { router.openEvent(event.id) }) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        ColorDot(agenda.color(for: event.account), size: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(event.allDay ? "Journée" : event.startAt.formatted(date: .omitted, time: .shortened))
                            .font(.meta.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.title).font(.rowTitle).foregroundStyle(.primary).lineLimit(1)
                            if let name = projectName(event.projectID) { Text(name).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        // Room for « Rejoindre », laid over the row so that its highlight runs to the end.
                        if joinable { Color.clear.frame(width: 32, height: 1) }
                    }
                    .opacity(event.endAt < now && !event.allDay ? 0.5 : 1)
                }
                .overlay(alignment: .trailing) {
                    if joinable {
                        IconButton("video.fill", help: "Rejoindre avec \(event.account)") { agenda.join(event) }
                    }
                }
            }
        }
    }

    /// Six projects in the board's order, then « Voir les N autres » (15/11: fifteen after the four statuses).
    private var urgentCard: some View {
        HomeCard(title: "Priorité 2", systemImage: "flag") {
            if urgent.isEmpty { EmptyLine("Aucun projet en priorité 2.") }
            ShowMoreList(urgent, limit: 6) { project in
                RowButton(action: { router.openProject(project.id) }) {
                    HStack(alignment: .center, spacing: Space.m) {
                        ProjectLogo(project, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(.rowTitle.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                            let detail = [project.todo, project.dueDate.map { "échéance \($0.formatted(date: .abbreviated, time: .omitted))" }]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !detail.isEmpty { Text(detail).font(.meta).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// The five latest meetings, each with the first line of its summary when there is one (15/11); the others
    /// are one click away, in Réunions.
    private var meetingsCard: some View {
        HomeCard(title: "Dernières réunions", systemImage: "waveform") {
            if library.rows.isEmpty { EmptyLine("Aucune réunion enregistrée.") }
            ForEach(library.rows.prefix(5)) { row in
                RowButton(action: { router.open(meetingID: row.id, at: nil) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.rowTitle).foregroundStyle(.primary).lineLimit(1)
                        Text([row.startedAt.formatted(date: .abbreviated, time: .shortened), projectName(row.projectID)]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.meta).foregroundStyle(.secondary).lineLimit(1)
                        if let overview = library.overviews[row.id] {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: Palette.violet))
                                Text(overview).font(.rowBody).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            if library.rows.count > 5 {
                TextButton("Toutes les réunions") { router.section = .meetings }
            }
        }
    }

    private var unfiledCard: some View {
        HomeCard(title: "À classer", systemImage: "tray") {
            if unfiled.isEmpty { EmptyLine("Tout est rangé.") }
            ShowMoreList(unfiled, limit: 5) { event in
                RowButton(action: { router.openEvent(event.id) }) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        Text(event.startAt.formatted(.dateTime.day().month(.abbreviated).locale(CalendarView.locale)))
                            .font(.meta.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                        Text(event.title).font(.rowTitle).foregroundStyle(.primary).lineLimit(1)
                    }
                }
            }
        }
    }
}

/// The next event, large, on a card tinted with its account's color (no glass under text, 15/11): « Détails » and
/// « Rejoindre », the page's main actions, in glass.
struct NextEventCard: View {
    let event: CalendarEventRow
    let now: Date
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @Environment(\.self) private var environment

    var body: some View {
        let color = agenda.color(for: event.account)
        HStack(alignment: .center, spacing: Space.l) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 6, height: 54)
            VStack(alignment: .leading, spacing: Space.xs) {
                // In a shade of the account's color that reads (correctifs, 15/11).
                Text(HomeModel.when(event, now: now).uppercased()).font(.meta.weight(.semibold)).foregroundStyle(color.readable(in: environment))
                Text(event.title).font(.title2.weight(.semibold)).lineLimit(2)
                Text([event.startAt.formatted(date: .omitted, time: .shortened) + " – " + event.endAt.formatted(date: .omitted, time: .shortened),
                      AccountStyle.label(for: event.account),
                      event.projectID.flatMap { id in agenda.projects.first { $0.id == id }?.name }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.rowBody)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.m)
            Button("Détails") { router.openEvent(event.id) }
                .buttonStyle(.glass)
                .controlSize(.large)
            if event.meetCode != nil {
                Button { agenda.join(event) } label: { Label("Rejoindre", systemImage: "video.fill") }
                    .buttonStyle(.glassProminent)
                    .tint(color)
                    .controlSize(.large)
                    .help("Ouvre le Meet dans Dia avec le compte \(event.account)")
            }
        }
        .padding(Space.l + Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Radius.hero, fill: color.opacity(0.1))
    }
}

/// A card of Accueil: a title, then its lines (the design system's card).
struct HomeCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        Card {
            SectionTitle(title, systemImage: systemImage)
            content
        }
    }
}
