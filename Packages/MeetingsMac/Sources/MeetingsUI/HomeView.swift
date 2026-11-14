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
}

/// Accueil: the next event to join, then today at a glance. Kept light on purpose: it will become a
/// conversation (Paul, 13/11).
struct HomeView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var library: MeetingLibrary
    @ObservedObject var router: WindowRouter

    private var calendar: Calendar { CalendarView.calendar }
    private var today: [CalendarEventRow] {
        agenda.shown.filter { calendar.isDateInToday($0.startAt) || ($0.allDay && $0.startAt <= .now && $0.endAt > .now) }
            .sorted { ($0.allDay ? 0 : 1, $0.startAt) < ($1.allDay ? 0 : 1, $1.startAt) }
    }
    private var urgent: [ProjectRow] { agenda.projects.filter { $0.status == .priorite1 } }
    /// Recent events with a recording but no project: one choice files the meeting and its guests.
    private var unfiled: [CalendarEventRow] {
        agenda.shown.filter { $0.projectID == nil && $0.meetingID != nil && $0.startAt > Date().addingTimeInterval(-14 * 86_400) }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(context.date)).font(.largeTitle.bold())
                        Text(summary).foregroundStyle(.secondary)
                    }
                    if let next = HomeModel.next(agenda.shown, now: context.date) {
                        NextEventCard(event: next, now: context.date, agenda: agenda, router: router)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                        todayCard(now: context.date)
                        urgentCard
                        meetingsCard
                        unfiledCard
                    }
                }
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.top, PageMetrics.top)
                .padding(.bottom, PageMetrics.bottom)
                .frame(maxWidth: PageMetrics.maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .windowTitle("Accueil")
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
                Text(agenda.accounts.isEmpty ? "Connecte tes agendas dans Calendrier." : "Aucun rendez-vous.").foregroundStyle(.secondary)
            }
            ForEach(today) { event in
                HStack(spacing: 10) {
                    Button { router.openEvent(event.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(agenda.color(for: event.account)).frame(width: 8, height: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(event.allDay ? "Journée" : event.startAt.formatted(date: .omitted, time: .shortened))
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title).lineLimit(1)
                                if let name = projectName(event.projectID) { Text(name).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .opacity(event.endAt < now && !event.allDay ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    if event.meetCode != nil, event.endAt > now, !event.allDay {
                        Button { agenda.join(event) } label: { Image(systemName: "video.fill") }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .help("Rejoindre avec \(event.account)")
                    }
                }
            }
        }
    }

    private var urgentCard: some View {
        HomeCard(title: "Priorité 1", systemImage: "flag") {
            if urgent.isEmpty { Text("Aucun projet en priorité 1.").foregroundStyle(.secondary) }
            ForEach(urgent) { project in
                Button { router.section = .projects } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(ProjectViews.cardHex(project.color).map(Color.init(hex:)) ?? .accentColor).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name)
                            let detail = [project.todo, project.dueDate.map { "échéance \($0.formatted(date: .abbreviated, time: .omitted))" }]
                                .compactMap { $0 }.joined(separator: " · ")
                            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var meetingsCard: some View {
        HomeCard(title: "Dernières réunions", systemImage: "waveform") {
            if library.rows.isEmpty { Text("Aucune réunion enregistrée.").foregroundStyle(.secondary) }
            ForEach(library.rows.prefix(5)) { row in
                Button { router.open(meetingID: row.id, at: nil) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).lineLimit(1)
                        Text([row.startedAt.formatted(date: .abbreviated, time: .shortened), projectName(row.projectID)]
                            .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var unfiledCard: some View {
        HomeCard(title: "À classer", systemImage: "tray") {
            if unfiled.isEmpty { Text("Tout est rangé.").foregroundStyle(.secondary) }
            ForEach(unfiled.prefix(8)) { event in
                Button { router.openEvent(event.id) } label: {
                    Text("\(event.startAt.formatted(date: .abbreviated, time: .omitted)) · \(event.title)").lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The next event, large, with « Rejoindre » under its account's color.
struct NextEventCard: View {
    let event: CalendarEventRow
    let now: Date
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter

    var body: some View {
        let color = agenda.color(for: event.account)
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 6, height: 54)
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeModel.when(event, now: now).uppercased()).font(.caption.weight(.semibold)).foregroundStyle(color)
                Text(event.title).font(.title2.weight(.semibold)).lineLimit(2)
                Text([event.startAt.formatted(date: .omitted, time: .shortened) + " – " + event.endAt.formatted(date: .omitted, time: .shortened),
                      AccountStyle.label(for: event.account),
                      event.projectID.flatMap { id in agenda.projects.first { $0.id == id }?.name }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
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
        .padding(18)
        .glassEffect(.regular.tint(color.opacity(0.12)), in: .rect(cornerRadius: Radius.hero))
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
