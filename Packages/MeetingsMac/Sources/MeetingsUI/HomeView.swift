import Agenda
import Colin
import Persistence
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

    /// « Aujourd'hui » (18/11): what is left of the day, the whole-day events first, then by the hour; neither
    /// what is over nor what Paul declined.
    static func today(_ events: [CalendarEventRow], now: Date, calendar: Calendar) -> [CalendarEventRow] {
        events.filter { event in
            guard event.endAt > now, event.attendees.first(where: \.isSelf)?.response != "declined" else { return false }
            return event.allDay ? event.startAt <= now : calendar.isDate(event.startAt, inSameDayAs: now)
        }
        .sorted { ($0.allDay ? 0 : 1, $0.startAt) < ($1.allDay ? 0 : 1, $1.startAt) }
    }

    /// The next event after today, shown when nothing is left of the day: neither a whole day nor a declined one.
    static func upcoming(_ events: [CalendarEventRow], now: Date, calendar: Calendar) -> CalendarEventRow? {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return events
            .filter { !$0.allDay && $0.startAt >= tomorrow && $0.attendees.first(where: \.isSelf)?.response != "declined" }
            .min { $0.startAt < $1.startAt }
    }

    /// « Demain 10:00 », « Jeudi 10:00 »: the day as « Le point » says it, at the head of a line.
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let label = Briefing.dayLabel(date, now: now, calendar: calendar)
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}

/// Accueil (18/11): Colin's column on the left (what is done, where Paul stands), the lists on the right (what waits
/// for his click, his day). In a narrow window the lists come first, Colin under them. Nothing is said twice.
struct HomeView: View {
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var router: WindowRouter
    @State private var layout = HomeLayout.columns

    var body: some View {
        Page(spacing: Space.l) {
            Group {
                switch layout {
                case .columns:
                    HStack(alignment: .top, spacing: Space.l) {
                        ColinHome(colin: colin)
                        lists.frame(width: HomeLayout.listsWidth)
                    }
                case .stacked:
                    VStack(alignment: .leading, spacing: Space.l) {
                        lists
                        ColinHome(colin: colin)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { layout = HomeLayout.of(width: $0) }
        }
        .windowTitle("Accueil")
        .modifier(HomeMailPanels(mails: mails, router: router))
        // The Accueil is before Paul: « Le point » is prepared when he is back. He goes to another page: his absence starts.
        .onAppear { colin.seen() }
        .onDisappear { colin.left() }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router)
            TodayCard(agenda: agenda, router: router)
        }
    }
}

/// A draft to read, a thread to answer: they open over the Accueil, which stays behind (18/11). Without the mails,
/// nothing opens.
private struct HomeMailPanels: ViewModifier {
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter

    func body(content: Content) -> some View {
        if let mails {
            content
                .mailPanels(mails, router: router, thread: $router.homeMail, browses: false, title: "Accueil", draftNews: false)
                .onAppear { mails.router = router }
        } else {
            content
        }
    }
}
