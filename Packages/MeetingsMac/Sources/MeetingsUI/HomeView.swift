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

/// Accueil (the Accueil's pass, 18/11): on the left, the conversation with Colin — his name fixed at its head, his
/// thread, his bar floating over it; on the right, « ta journée » (0.36.0) — the date and what came since, « Aujourd'hui »
/// (« Demain » in the evening), « À valider », « À faire ». In a narrow window, a strip of the day stays at the top,
/// « À valider » and « À faire » open over the thread.
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
    /// The narrow window's « À valider » and « À faire », open over the thread.
    @State private var reviewOpen = false
    /// « À faire »: who set each deadline, the first actions, Paul's « Reporter » and « Livré ».
    @StateObject private var todo: TodoLibrary
    /// The Claude accounts read from Vigie; `nil` in a window made without them: nothing is read from a capture.
    let accounts: ClaudeAccountsModel?

    init(agenda: AgendaLibrary, mails: MailLibrary?, colin: ColinLibrary, thread: ColinThread? = nil, router: WindowRouter,
         accounts: ClaudeAccountsModel? = nil) {
        self.agenda = agenda
        self.mails = mails
        self.colin = colin
        self.thread = thread
        self.router = router
        self.accounts = accounts
        _todo = StateObject(wrappedValue: TodoLibrary(database: agenda.database))
    }

    /// The projects of « À faire » with a date: what Colin's bar proposes to ask about.
    private var due: [String] {
        TodoRules.dated(todo.lines(projects: agenda.projects, events: agenda.shown), projects: agenda.projects).map(\.name)
    }

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
        .sheet(isPresented: $seeing) { ChangesSheet(colin: colin, router: router) }
        // The Accueil is before Paul: « Le point » is prepared when he is back. He goes to another page: his absence starts.
        .onAppear { colin.seen() }
        .onDisappear { colin.left() }
        // Vigie is read while the Accueil shows, never behind it.
        .task { await accounts?.watch() }
    }

    /// Two columns: the conversation, and the day at a fixed width; each scrolls alone.
    private var columns: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            if let thread { conversation(thread) }
            ScrollView {
                day
                    .padding(.top, PageMetrics.top)
                    .padding(.bottom, PageMetrics.bottom)
            }
            .belowToolbar()
            .frame(width: thread == nil ? nil : HomeLayout.listsWidth)
            .frame(maxWidth: thread == nil ? .infinity : nil)
        }
        .padding(.horizontal, PageMetrics.horizontal)
        .frame(maxWidth: PageMetrics.maxWidth)
        .frame(maxWidth: .infinity)
    }

    /// One column: a strip of the day at the top, the thread under it.
    private var stacked: some View {
        VStack(spacing: 0) {
            DayStrip(colin: colin, agenda: agenda, todo: todo, reviewOpen: $reviewOpen, seeing: $seeing)
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.vertical, Space.m)
            Divider()
            if let thread {
                conversation(thread)
                    .padding(.horizontal, PageMetrics.horizontal)
                    .overlay(alignment: .top) {
                        if reviewOpen {
                            ScrollView {
                                VStack(alignment: .leading, spacing: Space.l) {
                                    ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router, thresholds: colin.thresholds)
                                    TodoCard(todo: todo, agenda: agenda, router: router)
                                }
                                .padding(Space.m)
                            }
                            .frame(maxHeight: 340)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .padding(.horizontal, PageMetrics.horizontal)
                            .padding(.top, Space.s)
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                        }
                    }
            } else {
                ScrollView { day.padding(PageMetrics.horizontal) }
            }
        }
    }

    /// Colin's name, his thread, his bar: a view of its own, which follows the thread.
    private func conversation(_ thread: ColinThread) -> some View {
        ColinConversation(thread: thread, colin: colin, agenda: agenda, mails: mails, router: router, due: due, barHeight: $barHeight)
    }

    /// « Ta journée » (0.37.0, in cards): the point on the page, then « Aujourd'hui » put forward, « À valider », « À
    /// faire », « Comptes Claude ».
    private var day: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let preparedAt = colin.briefingAt, !colin.briefing.isEmpty {
                BriefingCard(sentences: colin.briefing, preparedAt: preparedAt,
                             see: colin.briefingChanges.isEmpty && colin.briefingMails.isEmpty ? nil : { seeing = true })
                    .transition(.opacity)
            }
            TodayCard(agenda: agenda, router: router)
                .padding(.top, Space.s)
            ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router, thresholds: colin.thresholds)
            TodoCard(todo: todo, agenda: agenda, router: router)
            if let accounts { ClaudeAccountsCard(model: accounts) }
        }
        .animation(Motion.standard, value: colin.briefingAt)
    }
}

/// The conversation with Colin (the Accueil's pass, 18/11): his name fixed at its head, his thread opened on its end,
/// his bar floating over it. It follows what Colin writes only while Paul is at the end; a question of his always
/// brings him there; otherwise ↓.
private struct ColinConversation: View {
    @ObservedObject var thread: ColinThread
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var agenda: AgendaLibrary
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    /// The projects of « À faire » with a date, for the questions over the bar.
    let due: [String]
    @Binding var barHeight: CGFloat
    @State private var position = ScrollPosition(edge: .bottom)
    /// Whether the thread follows its end: Paul's hand on it, and where the end stands.
    @State private var follow = ThreadFollow()

    var body: some View {
        VStack(spacing: 0) {
            ColinHeader(thread: thread, router: router)
                .frame(maxWidth: ThreadMetrics.column)
                .frame(maxWidth: .infinity)
                .padding(.top, PageMetrics.top)
                .padding(.bottom, Space.s)
            ScrollView {
                ColinThreadView(thread: thread, mails: mails, router: router)
                    .padding(.top, Space.s)
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
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            }
        }
    }
}

/// The narrow window's day, in one strip (0.36.0): the date and « Voir »; the next meeting — tomorrow's first in the
/// evening — with « Rejoindre », and « À valider · À faire », which opens over the thread.
private struct DayStrip: View {
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var todo: TodoLibrary
    @Binding var reviewOpen: Bool
    @Binding var seeing: Bool
    @AppStorage(Preferences.Key.homeTomorrowFrom) private var tomorrowFrom = Preferences.Default.homeTomorrowFrom

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let calendar = CalendarView.calendar
            let shown = HomeModel.dayShown(agenda.shown, now: context.date, tomorrowFrom: tomorrowFrom, calendar: calendar)
            let next = shown.tomorrow ? shown.events.first { !$0.allDay } : HomeModel.next(agenda.shown, now: context.date, calendar: calendar)
            let todoCount = todo.lines(projects: agenda.projects, events: agenda.shown).count
            // Two lines: the day; the next meeting and what waits.
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .center, spacing: Space.s) {
                    Text(BriefingText.today(context.date, calendar: calendar)).font(.headline).lineLimit(1).fixedSize()
                    if !colin.briefingChanges.isEmpty || !colin.briefingMails.isEmpty {
                        TextButton("Voir", quiet: true) { seeing = true }.fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: Space.s) {
                    if let next {
                        Text("\(shown.tomorrow ? "Demain " : "")\(next.startAt.formatted(date: .omitted, time: .shortened)) \(next.title)")
                            .font(.meta).foregroundStyle(.secondary).lineLimit(1)
                        if next.meetCode != nil, !shown.tomorrow || next.startAt.timeIntervalSince(context.date) <= 600 {
                            Group {
                                if next.startAt.timeIntervalSince(context.date) <= 600 {
                                    Button { agenda.join(next) } label: { Label("Rejoindre", systemImage: "video.fill") }
                                        .buttonStyle(.glassProminent).controlSize(.small)
                                } else {
                                    Button { agenda.join(next) } label: { Label("Rejoindre", systemImage: "video") }.buttonStyle(.subtle)
                                }
                            }
                            .fixedSize()
                        }
                    }
                    Spacer(minLength: Space.s)
                    Button("À valider \(colin.review.count) · À faire \(todoCount)") { withAnimation(Motion.quick) { reviewOpen.toggle() } }
                        .buttonStyle(.subtle)
                        .fixedSize()
                }
            }
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
