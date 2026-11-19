import Persistence
import PolhubDesign
import SwiftUI

/// The words of « Aujourd'hui ».
enum TodayText {
    /// The next meeting's line: when, its hour unless « when » says it, its project (final review, 18/11).
    static func next(when: String, hour: String, project: String?) -> String {
        ([when] + (when.contains(hour) ? [] : [hour]) + [project].compactMap { $0 }).joined(separator: " · ")
    }
}

/// « Aujourd'hui » (the Accueil's pass, 18/11): the next meeting large — its countdown in the color of attention from a
/// quarter of an hour, « Rejoindre » the principal button ten minutes before (design system v2, 19/11) —, the others on
/// one line each; when nothing is left, the next one.
/// In the evening (0.36.0), from the hour set in Réglages › Calendrier and once the day's last meeting is over:
/// « Demain · jeudi 19 novembre », tomorrow's meetings.
struct TodayCard: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @AppStorage(Preferences.Key.homeTomorrowFrom) private var tomorrowFrom = Preferences.Default.homeTomorrowFrom

    private var calendar: Calendar { CalendarView.calendar }

    var body: some View {
        // The minutes pass: « dans 12 min », then « en cours ».
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let shown = HomeModel.dayShown(agenda.shown, now: now, tomorrowFrom: tomorrowFrom, calendar: calendar)
            let next = shown.tomorrow ? shown.events.first { !$0.allDay } : HomeModel.next(agenda.shown, now: now, calendar: calendar)
            // The card put forward (0.37.0): the first of the day; as round as the others (design system v2, 19/11).
            HomeCard(shown.title) {
                if shown.events.isEmpty {
                    let day = shown.tomorrow ? calendar.date(byAdding: .day, value: 1, to: now) ?? now : now
                    if shown.tomorrow, !agenda.accounts.isEmpty { EmptyLine("Rien demain.") }
                    if let coming = HomeModel.upcoming(agenda.shown, after: day, calendar: calendar) {
                        upcoming(coming, now: now)
                    } else if !shown.tomorrow || agenda.accounts.isEmpty {
                        EmptyLine(agenda.accounts.isEmpty ? "Connecte tes agendas dans Calendrier." : "Aucun rendez-vous.")
                    }
                }
                let hasNext = next.map { next in shown.events.contains { $0.id == next.id } } ?? false
                if let next, hasNext { nextRow(next, now: now) }
                let others = shown.events.filter { $0.id != next?.id }
                ShowMoreList(others, limit: 5) { event in row(event, now: now).homeRow(first: !hasNext && event.id == others.first?.id) }
            }
        }
    }

    private func projectName(_ id: UUID?) -> String? {
        id.flatMap { id in agenda.projects.first { $0.id == id }?.name }
    }

    /// Minutes before it starts (negative once begun).
    private func minutes(to event: CalendarEventRow, now: Date) -> Double { event.startAt.timeIntervalSince(now) / 60 }

    /// The next meeting, large.
    private func nextRow(_ event: CalendarEventRow, now: Date) -> some View {
        let joinable = event.meetCode != nil && !event.allDay
        let left = minutes(to: event, now: now)
        let soon = left <= 15
        let when = HomeModel.when(event, now: now)
        let rest = TodayText.next(when: when, hour: event.startAt.formatted(date: .omitted, time: .shortened), project: projectName(event.projectID))
            .dropFirst(when.count)
        return RowButton(action: { router.openEvent(event.id) }) {
            HStack(alignment: .center, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.title3.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    HStack(spacing: 0) {
                        // « dans 12 min »: soon, the color of attention (design system v2, 19/11).
                        Text(when).foregroundStyle(soon ? AnyShapeStyle(Tint.attention) : AnyShapeStyle(.secondary))
                            .fontWeight(soon ? .semibold : .regular)
                        Text(String(rest)).foregroundStyle(.secondary)
                    }
                    .font(.meta.monospacedDigit())
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                if joinable, left <= 10 || calendar.isDate(event.startAt, inSameDayAs: now) { Color.clear.frame(width: 108, height: 1) }
            }
            .padding(.vertical, Space.xs)
        }
        .overlay(alignment: .trailing) {
            // Far off (tomorrow's first, from the evening): no « Rejoindre » before its last ten minutes.
            if joinable, left <= 10 || calendar.isDate(event.startAt, inSameDayAs: now) {
                if left <= 10 {
                    // The Accueil's one principal button, ten minutes before: full and matte, at the accent; no glass
                    // in the content (design system v2, 19/11).
                    Button { agenda.join(event) } label: { Label("Rejoindre", systemImage: "video.fill") }
                        .buttonStyle(.primary)
                        .controlSize(.small)
                        .help("Ouvre le Meet dans Dia avec le compte \(event.account)")
                } else {
                    Button { agenda.join(event) } label: { Label("Rejoindre", systemImage: "video") }
                        .buttonStyle(.subtle)
                        .help("Ouvre le Meet dans Dia avec le compte \(event.account)")
                }
            }
        }
    }

    /// Another meeting of the day, on one line: its hour in a column, its title, its project.
    private func row(_ event: CalendarEventRow, now: Date) -> some View {
        let joinable = event.meetCode != nil && !event.allDay
        return RowButton(action: { router.openEvent(event.id) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(event.allDay ? "Journée" : event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.meta.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                Text(event.title).font(.rowBody).foregroundStyle(.primary).lineLimit(1)
                Spacer(minLength: Space.s)
                if let project = projectName(event.projectID) { Text(project).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                if joinable { Color.clear.frame(width: 28, height: 1) }
            }
        }
        .overlay(alignment: .trailing) {
            if joinable { IconButton("video", help: "Rejoindre avec \(event.account)") { agenda.join(event) } }
        }
    }

    /// Nothing is left today: the next event, with its day.
    private func upcoming(_ event: CalendarEventRow, now: Date) -> some View {
        RowButton(action: { router.openEvent(event.id) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.rowTitle).foregroundStyle(.primary).lineLimit(1)
                    Text([HomeModel.dayLabel(event.startAt, now: now, calendar: calendar), projectName(event.projectID)].compactMap { $0 }.joined(separator: " · "))
                        .font(.meta.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
