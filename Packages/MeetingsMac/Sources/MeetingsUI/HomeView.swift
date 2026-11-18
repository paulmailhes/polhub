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

/// Accueil (18/11): Colin's column on the left (what is done, where Paul stands, his thread and his bar), the lists on
/// the right (what waits for his click, his day). In two columns each scrolls alone and the bar stays under Colin's;
/// in a narrow window the lists come first, Colin under them, the bar at the bottom. Nothing is said twice.
struct HomeView: View {
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var colin: ColinLibrary
    /// `nil`: no bar (captures without the engine).
    var thread: ColinThread?
    @ObservedObject var router: WindowRouter
    @State private var layout = HomeLayout.columns
    /// The bar's height, for the bar of a sending to stay above it.
    @State private var barHeight: CGFloat = 0
    /// Where Colin's thread stands; it follows its end only while Paul is there (the Accueil's pass, 18/11).
    @State private var threadPosition = ScrollPosition(edge: .bottom)
    @State private var following = true

    var body: some View {
        Group {
            switch layout {
            case .columns: columns
            case .stacked: stacked
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            layout = HomeLayout.of(width: min(width, PageMetrics.maxWidth) - 2 * PageMetrics.horizontal)
        }
        .windowTitle("Accueil")
        .modifier(HomeMailPanels(mails: mails, router: router, lift: barHeight))
        // The Accueil is before Paul: « Le point » is prepared when he is back. He goes to another page: his absence starts.
        .onAppear { colin.seen() }
        .onDisappear { colin.left() }
    }

    /// Two columns, each scrolling alone; the bar under Colin's, outside his scroll.
    private var columns: some View {
        HStack(alignment: .top, spacing: Space.l) {
            VStack(spacing: 0) {
                ScrollView {
                    ColinHome(colin: colin, thread: thread, mails: mails, router: router)
                        .padding(.top, PageMetrics.top)
                        .padding(.bottom, Space.l)
                }
                // Opened on the last exchanges; a short thread stays at the top.
                .scrollPosition($threadPosition)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .scrollIndicators(.automatic)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    ThreadScroll.follows(contentHeight: geometry.contentSize.height, offset: geometry.visibleRect.minY, visibleHeight: geometry.visibleRect.height)
                } action: { _, atEnd in
                    following = atEnd
                }
                // What Colin writes is followed only while Paul is at the end; a question of his always brings him there.
                .onChange(of: thread?.visible) { _, _ in if following { threadPosition.scrollTo(edge: .bottom) } }
                .onChange(of: thread.flatMap { ColinThreadText.lastID($0.messages, changes: $0.changes) }) { _, _ in
                    if following || thread?.messages.last?.author == .paul { withAnimation(Motion.standard) { threadPosition.scrollTo(edge: .bottom) } }
                }
                .overlay(alignment: .bottom) {
                    if !following {
                        JumpToEnd { withAnimation(Motion.standard) { threadPosition.scrollTo(edge: .bottom) } }
                            .padding(.bottom, Space.s)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.quick, value: following)
                if let thread { bar(thread) }
            }
            ScrollView {
                lists
                    .padding(.top, PageMetrics.top)
                    .padding(.bottom, PageMetrics.bottom)
            }
            .frame(width: HomeLayout.listsWidth)
        }
        .padding(.horizontal, PageMetrics.horizontal)
        .frame(maxWidth: PageMetrics.maxWidth)
        .frame(maxWidth: .infinity)
    }

    /// One page: the lists, then Colin; the bar at the bottom, over the whole width.
    private var stacked: some View {
        Page(spacing: Space.l) {
            lists
            ColinHome(colin: colin, thread: thread, mails: mails, router: router)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let thread { bar(thread).padding(.horizontal, PageMetrics.horizontal - Space.xl) }
        }
    }

    private func bar(_ thread: ColinThread) -> some View {
        ColinComposer(thread: thread)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
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
    /// Colin's bar: the bar of a sending stays above it.
    var lift: CGFloat = 0

    func body(content: Content) -> some View {
        if let mails {
            content
                .mailPanels(mails, router: router, thread: $router.homeMail, browses: false, title: "Accueil", draftNews: false, lift: lift)
                .onAppear { mails.router = router }
        } else {
            content
        }
    }
}
