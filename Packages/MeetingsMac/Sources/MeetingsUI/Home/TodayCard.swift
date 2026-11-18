import Persistence
import PolhubDesign
import SwiftUI

/// « Aujourd'hui » (18/11): what is left of the day, the next event first with « Rejoindre »; when nothing is left,
/// the next one (« Demain 10:00 »).
struct TodayCard: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter

    private var calendar: Calendar { CalendarView.calendar }
    /// The room kept at the end of a line for « Rejoindre », as a word or as an icon.
    private static let joinWidth: CGFloat = 112
    private static let iconWidth: CGFloat = 32

    var body: some View {
        // The minutes pass: « dans 12 min », then « en cours ».
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            let today = HomeModel.today(agenda.shown, now: now, calendar: calendar)
            let next = HomeModel.next(agenda.shown, now: now, calendar: calendar)
            Card {
                SectionTitle("Aujourd'hui")
                if today.isEmpty {
                    if let coming = HomeModel.upcoming(agenda.shown, now: now, calendar: calendar) {
                        upcoming(coming, now: now)
                    } else {
                        EmptyLine(agenda.accounts.isEmpty ? "Connecte tes agendas dans Calendrier." : "Aucun rendez-vous.")
                    }
                }
                ShowMoreList(today, limit: 6) { event in row(event, isNext: event.id == next?.id, now: now) }
            }
        }
    }

    private func projectName(_ id: UUID?) -> String? {
        id.flatMap { id in agenda.projects.first { $0.id == id }?.name }
    }

    private func row(_ event: CalendarEventRow, isNext: Bool, now: Date) -> some View {
        let joinable = event.meetCode != nil && !event.allDay
        // The next one says when (« dans 40 min », « en cours »), beside « Rejoindre »; the others their project.
        let detail = isNext ? HomeModel.when(event, now: now) : projectName(event.projectID) ?? ""
        return RowButton(action: { router.openEvent(event.id) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                ColorDot(agenda.color(for: event.account), size: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(event.allDay ? "Journée" : event.startAt.formatted(date: .omitted, time: .shortened))
                    .font(.meta.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.rowTitle.weight(isNext ? .medium : .regular)).foregroundStyle(.primary).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(.meta).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                // Room for « Rejoindre », laid over the row so that its highlight runs to the end.
                if joinable { Color.clear.frame(width: isNext ? Self.joinWidth : Self.iconWidth, height: 1) }
            }
        }
        .overlay(alignment: .trailing) {
            if joinable {
                if isNext {
                    Button { agenda.join(event) } label: { Label("Rejoindre", systemImage: "video.fill") }
                        .buttonStyle(.glassProminent)
                        .tint(agenda.color(for: event.account))
                        .controlSize(.small)
                        .help("Ouvre le Meet dans Dia avec le compte \(event.account)")
                } else {
                    IconButton("video.fill", help: "Rejoindre avec \(event.account)") { agenda.join(event) }
                }
            }
        }
    }

    /// Nothing is left today: the next event, with its day.
    private func upcoming(_ event: CalendarEventRow, now: Date) -> some View {
        RowButton(action: { router.openEvent(event.id) }) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                ColorDot(agenda.color(for: event.account), size: 8).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
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
