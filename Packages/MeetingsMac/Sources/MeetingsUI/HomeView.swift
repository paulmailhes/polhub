import Domain
import Persistence
import ProjectsUI
import SwiftUI

/// Accueil: today at a glance. Kept light on purpose: it will become a conversation (Paul, 13/11).
struct HomeView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var library: MeetingLibrary
    @ObservedObject var router: WindowRouter

    private var calendar: Calendar { CalendarView.calendar }
    private var today: [CalendarEventRow] {
        agenda.events.filter { calendar.isDateInToday($0.startAt) || ($0.allDay && $0.startAt <= .now && $0.endAt > .now) }
    }
    private var urgent: [ProjectRow] { agenda.projects.filter { $0.status == .priorite1 } }
    /// Recent events with a recording but no project: one choice files the meeting and its guests.
    private var unfiled: [CalendarEventRow] {
        agenda.events.filter { $0.projectID == nil && $0.meetingID != nil && $0.startAt > Date().addingTimeInterval(-14 * 86_400) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text({ let text = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
                           return text.prefix(1).uppercased() + text.dropFirst() }())
                        .font(.largeTitle.bold())
                    Text(summary).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 24) {
                    card("Aujourd'hui", systemImage: "calendar") {
                        if today.isEmpty {
                            Text(agenda.accounts.isEmpty ? "Connecte tes agendas dans Calendrier." : "Aucun rendez-vous.").foregroundStyle(.secondary)
                        }
                        ForEach(today) { event in
                            Button { router.section = .calendar } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(event.allDay ? "Journée" : event.startAt.formatted(date: .omitted, time: .shortened))
                                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.title)
                                        if let name = projectName(event.projectID) { Text(name).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    card("Priorité 1", systemImage: "flag") {
                        if urgent.isEmpty { Text("Aucun projet en priorité 1.").foregroundStyle(.secondary) }
                        ForEach(urgent) { project in
                            Button { router.section = .projects } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(project.name)
                                    Text([project.todo, project.dueDate.map { "échéance \($0.formatted(date: .abbreviated, time: .omitted))" }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 24) {
                    card("Dernières réunions", systemImage: "waveform") {
                        ForEach(library.rows.prefix(5)) { row in
                            Button { router.open(meetingID: row.id, at: nil) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title)
                                    Text([row.startedAt.formatted(date: .abbreviated, time: .shortened), projectName(row.projectID)]
                                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    card("À classer", systemImage: "tray") {
                        if unfiled.isEmpty { Text("Tout est rangé.").foregroundStyle(.secondary) }
                        ForEach(unfiled.prefix(8)) { event in
                            Button { router.section = .calendar } label: {
                                Text("\(event.startAt.formatted(date: .abbreviated, time: .omitted)) · \(event.title)")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var summary: String {
        let count = today.filter { !$0.allDay }.count
        return count == 0 ? "Pas de rendez-vous aujourd'hui." : "\(count) rendez-vous aujourd'hui."
    }

    private func projectName(_ id: UUID?) -> String? {
        id.flatMap { id in agenda.projects.first { $0.id == id }?.name }
    }

    private func card<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
