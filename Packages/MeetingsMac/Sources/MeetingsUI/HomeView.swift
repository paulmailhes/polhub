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

/// Accueil (the Accueil's pass, 18/11): on the left, the conversation with Colin — his name fixed at its head, his
/// thread, his bar floating over it; on the right, « ta journée » — « Le point » in figures, « Aujourd'hui », « À
/// valider ». In a narrow window, a strip of the day stays at the top, « À valider » opens over the thread.
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
    /// The narrow window's « À valider », open over the thread.
    @State private var reviewOpen = false

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
            DayStrip(colin: colin, agenda: agenda, thread: thread, reviewOpen: $reviewOpen, seeing: $seeing)
                .padding(.horizontal, PageMetrics.horizontal)
                .padding(.vertical, Space.m)
            Divider()
            if let thread {
                conversation(thread)
                    .padding(.horizontal, PageMetrics.horizontal)
                    .overlay(alignment: .top) {
                        if reviewOpen {
                            ScrollView {
                                ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router, thresholds: colin.thresholds).padding(Space.l)
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
        ColinConversation(thread: thread, colin: colin, agenda: agenda, mails: mails, router: router, barHeight: $barHeight)
    }

    /// « Ta journée »: the point, today, what waits.
    private var day: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let preparedAt = colin.briefingAt, !colin.briefing.isEmpty {
                BriefingCard(sentences: colin.briefing, preparedAt: preparedAt, figures: colin.briefingFigures,
                             see: colin.briefingChanges.isEmpty && colin.briefingMails.isEmpty ? nil : { seeing = true },
                             ask: thread.map { thread in { thread.fill($0) } })
                    .transition(.opacity)
            }
            TodayCard(agenda: agenda, router: router)
            Divider()
            ReviewCard(colin: colin, agenda: agenda, mails: mails, router: router, thresholds: colin.thresholds)
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
                ColinComposer(thread: thread, review: colin.review,
                              due: Briefing.due(agenda.projects, now: Date(), calendar: CalendarView.calendar).map(\.name))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
            }
        }
    }
}

/// The narrow window's day, in one strip (final review, 18/11): the date, the figures (a click asks Colin), « Voir »,
/// the next meeting with « Rejoindre », and « À valider » that opens over the thread.
private struct DayStrip: View {
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var agenda: AgendaLibrary
    var thread: ColinThread?
    @Binding var reviewOpen: Bool
    @Binding var seeing: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let next = HomeModel.next(agenda.shown, now: context.date, calendar: CalendarView.calendar)
            // Two lines: the day and its figures; the next meeting and what waits.
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .center, spacing: Space.s) {
                    Text(BriefingText.today(context.date, calendar: CalendarView.calendar)).font(.headline).lineLimit(1).fixedSize()
                    if let figures = colin.briefingFigures {
                        ForEach(figures.tiles, id: \.tile) { figure in
                            Button("\(figure.count) \(Briefing.label(figure.tile, count: figure.count))") { thread?.fill(Briefing.question(for: figure.tile)) }
                                .buttonStyle(.subtle)
                                .fixedSize()
                        }
                    }
                    if !colin.briefingChanges.isEmpty || !colin.briefingMails.isEmpty {
                        TextButton("Voir", quiet: true) { seeing = true }.fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                HStack(alignment: .center, spacing: Space.s) {
                    if let next {
                        Text("\(next.startAt.formatted(date: .omitted, time: .shortened)) \(next.title)").font(.meta).foregroundStyle(.secondary).lineLimit(1)
                        if next.meetCode != nil {
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
                    Button("À valider \(colin.review.count)") { withAnimation(Motion.quick) { reviewOpen.toggle() } }
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
