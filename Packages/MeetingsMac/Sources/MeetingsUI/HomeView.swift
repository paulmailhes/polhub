import Agenda
import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// The day the Accueil shows: today, or tomorrow in the evening (0.36.0).
struct DayShown: Equatable {
    var tomorrow: Bool
    /// « Aujourd'hui », « Demain · jeudi 19 novembre ».
    var title: String
    var events: [CalendarEventRow]
}

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

    /// The first event after `day`'s end: neither a whole day nor a declined one. Tomorrow shown and empty, the next one.
    static func upcoming(_ events: [CalendarEventRow], after day: Date, calendar: Calendar) -> CalendarEventRow? {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        return events
            .filter { !$0.allDay && $0.startAt >= end && $0.attendees.first(where: \.isSelf)?.response != "declined" }
            .min { $0.startAt < $1.startAt }
    }

    /// « Aujourd'hui », or « Demain » (0.36.0): from `tomorrowFrom` (minutes after midnight) and once no meeting of
    /// today is left, the day shown is tomorrow — its whole days first, then by the hour, never what Paul declined.
    static func dayShown(_ events: [CalendarEventRow], now: Date, tomorrowFrom: Int, calendar: Calendar) -> DayShown {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let today = Self.today(events, now: now, calendar: calendar)
        guard minutes >= tomorrowFrom, !today.contains(where: { !$0.allDay }),
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return DayShown(tomorrow: false, title: "Aujourd'hui", events: today)
        }
        let said = BriefingText.today(tomorrow, calendar: calendar)
        let shown = events.filter { event in
            guard event.attendees.first(where: \.isSelf)?.response != "declined" else { return false }
            return event.allDay ? event.startAt <= tomorrow && event.endAt > tomorrow : calendar.isDate(event.startAt, inSameDayAs: tomorrow)
        }
        .sorted { ($0.allDay ? 0 : 1, $0.startAt) < ($1.allDay ? 0 : 1, $1.startAt) }
        return DayShown(tomorrow: true, title: "Demain · " + said.prefix(1).lowercased() + said.dropFirst(), events: shown)
    }

    /// « Demain 10:00 », « Jeudi 10:00 »: the day as « Le point » says it, at the head of a line.
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let label = Briefing.dayLabel(date, now: now, calendar: calendar)
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}

/// Accueil (lot 5, 19/11, « Colin à droite »): the day is the page — its date as the title, what came since, « Aujourd'hui »
/// (« Demain » in the evening), « À valider », « À faire » —, its column 640 points at most; Colin is a panel at the right
/// edge, 420 points, the whole height, on his own ground, his bar at its foot the only glass. In a narrow window, the day
/// alone: Colin's bar floats at its foot and opens his thread in a panel over the day, which Échap closes.
struct HomeView: View {
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var colin: ColinLibrary
    /// `nil`: no thread nor bar (captures without the engine, the public build without the mails): the day alone.
    var thread: ColinThread?
    @ObservedObject var router: WindowRouter
    @State private var layout = HomeLayout.columns
    /// The bar's height, for the bar of a sending to stay above it.
    @State private var barHeight: CGFloat = 0
    /// « Voir »: what moved without Paul, over the Accueil.
    @State private var seeing = false
    /// The narrow window: Colin's thread, open over the day.
    @State private var threadOpen = false
    /// « À faire »: who set each deadline, the first actions, Paul's « Reporter » and « Livré ».
    @StateObject private var todo: TodoLibrary
    /// The Claude accounts read from Vigie; `nil` in a window made without them: nothing is read from a capture.
    let accounts: ClaudeAccountsModel?

    /// `threadOpen`: the narrow window's thread open over the day, for the captures.
    init(agenda: AgendaLibrary, mails: MailLibrary?, colin: ColinLibrary, thread: ColinThread? = nil, router: WindowRouter,
         accounts: ClaudeAccountsModel? = nil, threadOpen: Bool = false) {
        self.agenda = agenda
        self.mails = mails
        self.colin = colin
        self.thread = thread
        self.router = router
        self.accounts = accounts
        _todo = StateObject(wrappedValue: TodoLibrary(database: agenda.database))
        _threadOpen = State(initialValue: threadOpen)
    }

    /// The projects of « À faire » with a date: what Colin's bar proposes to ask about.
    private var due: [String] {
        TodoRules.dated(todo.lines(projects: agenda.projects, events: agenda.shown), projects: agenda.projects).map(\.name)
    }

    var body: some View {
        Group {
            if let thread {
                switch layout {
                case .columns: columns(thread)
                case .stacked: stacked(thread)
                }
            } else {
                dayPage
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in layout = HomeLayout.of(width: width) }
        // Wide again: the thread is in its panel, nothing floats over the day.
        .onChange(of: layout) { _, now in if now == .columns { threadOpen = false } }
        .windowTitle("Accueil")
        .modifier(HomeMailPanels(mails: mails, router: router, lift: barHeight))
        .sheet(isPresented: $seeing) { ChangesSheet(colin: colin, router: router) }
        // The Accueil is before Paul: « Le point » is prepared when he is back. He goes to another page: his absence starts.
        .onAppear { colin.seen() }
        .onDisappear { colin.left() }
        // Vigie is read while the Accueil shows, never behind it.
        .task { await accounts?.watch() }
    }

    /// The day, a page that scrolls: its column 640 points at most, in the middle of what the panel leaves.
    private var dayPage: some View {
        ScrollView {
            day
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.top, PageMetrics.top)
                .padding(.bottom, PageMetrics.bottom)
                .frame(maxWidth: HomeLayout.dayWidth + 2 * PageMetrics.horizontal)
                .frame(maxWidth: .infinity)
        }
        .belowToolbar()
    }

    /// The day on the left; Colin's panel on the right, on its own ground, a line between them, the whole height.
    private func columns(_ thread: ColinThread) -> some View {
        HStack(spacing: 0) {
            dayPage
            Divider().ignoresSafeArea(edges: .vertical)
            ColinPanel(thread: thread, colin: colin, mails: mails, router: router, due: due, barHeight: $barHeight)
                .frame(width: HomeLayout.panelWidth)
                .background(Surface.fill)
        }
    }

    /// The narrow window: the day alone, Colin's bar floating at its foot; his thread opens over the day.
    private func stacked(_ thread: ColinThread) -> some View {
        dayPage
            .safeAreaBar(edge: .bottom) {
                if !threadOpen {
                    ColinComposer(thread: thread, review: colin.review, due: due, open: { threadOpen = true })
                        .padding(.horizontal, PageMetrics.horizontal)
                        .padding(.bottom, Space.m)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                }
            }
            .overlay {
                if threadOpen {
                    FloatingPanel(close: { threadOpen = false }) {
                        ColinPanel(thread: thread, colin: colin, mails: mails, router: router, due: due, barHeight: $barHeight,
                                   close: { threadOpen = false })
                            .background(Surface.fill)
                    }
                }
            }
            .animation(Motion.standard, value: threadOpen)
    }

    /// « Ta journée »: its date and what came since, then « Aujourd'hui » put forward, « À valider », « À faire », « Comptes
    /// Claude ».
    private var day: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            DayHeader(sentences: colin.briefingAt == nil ? [] : colin.briefing, preparedAt: colin.briefingAt,
                      see: colin.briefingChanges.isEmpty && colin.briefingMails.isEmpty ? nil : { seeing = true })
            TodayCard(agenda: agenda, router: router)
                .padding(.top, Space.s)
            ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router, thresholds: colin.thresholds)
            TodoCard(todo: todo, agenda: agenda, router: router)
            if let accounts { ClaudeAccountsCard(model: accounts) }
        }
        .animation(Motion.standard, value: colin.briefingAt)
    }
}

/// Colin's panel (lot 5, 19/11): his name and his state at its head, a line, his thread fading under it, his bar at its
/// foot. Docked at the right of the window; or floating over the day in a narrow one, with ✕ (`close`), Échap closing it.
private struct ColinPanel: View {
    @ObservedObject var thread: ColinThread
    @ObservedObject var colin: ColinLibrary
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    let due: [String]
    @Binding var barHeight: CGFloat
    var close: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ColinHeader(thread: thread, router: router, close: close)
                .padding(.horizontal, Space.l)
                .padding(.top, PageMetrics.top)
                .padding(.bottom, Space.m)
            Divider()
            ColinConversation(thread: thread, colin: colin, mails: mails, router: router, due: due, barHeight: $barHeight)
        }
        // Floating over the day, it takes the keys at once: Échap closes it before any click in it.
        .focusable(close != nil)
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { if close != nil { focused = true } }
    }
}

/// Colin's thread and his bar (the Accueil's pass, 18/11): the thread opened on its end, his bar floating over its foot. It
/// follows what Colin writes only while Paul is at the end; a question of his always brings him there; otherwise ↓. At
/// its top, under the line of the panel's head, the thread fades (lot 5, 19/11).
private struct ColinConversation: View {
    @ObservedObject var thread: ColinThread
    @ObservedObject var colin: ColinLibrary
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    /// The projects of « À faire » with a date, for the questions over the bar.
    let due: [String]
    @Binding var barHeight: CGFloat
    @State private var position = ScrollPosition(edge: .bottom)
    /// Whether the thread follows its end: Paul's hand on it, and where the end stands.
    @State private var follow = ThreadFollow()

    var body: some View {
        ScrollView {
            ColinThreadView(thread: thread, mails: mails, router: router)
                .padding(.horizontal, Space.l)
                // Nothing fades at rest: the thread starts under its fade.
                .padding(.top, ThreadMetrics.fade)
                .padding(.bottom, Space.l)
        }
        // Opened on the last exchanges; a short thread stays at the top.
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollIndicators(.automatic)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            ThreadScroll.follows(contentHeight: geometry.contentSize.height, offset: geometry.visibleRect.minY, visibleHeight: geometry.visibleRect.height)
        } action: { _, atEnd in
            // The thread grew while it followed (a word, a card, a foot): to its end. Paul's hand decides the rest.
            if follow.geometry(atEnd: atEnd) { position.scrollTo(edge: .bottom) }
        }
        .onScrollPhaseChange { _, phase in
            // Only Paul's own hand: a scroll animated by the code is not him going up.
            let hand = phase == .interacting || phase == .decelerating
            if hand != follow.userScrolling { follow.userScroll(began: hand) }
        }
        .onChange(of: thread.visible) { _, _ in if follow.scrollsOnTick { position.scrollTo(edge: .bottom) } }
        .onChange(of: thread.liveSteps) { _, _ in if follow.scrollsOnTick { position.scrollTo(edge: .bottom) } }
        .onChange(of: ColinThreadText.lastID(thread.messages, changes: thread.changes)) { _, _ in
            if follow.scrollsOnTick { withAnimation(Motion.standard) { position.scrollTo(edge: .bottom) } }
        }
        // A question of Paul's always brings him to the end.
        .onChange(of: thread.messages.last(where: { $0.author == .paul })?.id) { _, _ in
            follow.asked()
            withAnimation(Motion.standard) { position.scrollTo(edge: .bottom) }
        }
        // Under the line of the head, the thread fades over 16 points instead of being cut.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: ThreadMetrics.fade)
                Rectangle()
            }
        }
        .overlay(alignment: .bottom) {
            if !follow.following {
                JumpToEnd {
                    follow.asked()
                    withAnimation(Motion.standard) { position.scrollTo(edge: .bottom) }
                }
                .padding(.bottom, Space.s)
                .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: follow.following)
        // The bar floats over the thread, which passes under its glass.
        .safeAreaBar(edge: .bottom) {
            ColinComposer(thread: thread, review: colin.review, due: due)
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.m)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
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
