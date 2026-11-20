import HubLink
import SwiftUI

/// Calendrier (Paul, 20/11): two days side by side, the hours one after the other, as on the Mac; the list of the
/// coming fortnight stays, one touch away. « Rejoindre » opens the Meet.
struct CalendarScreen: View {
    enum Mode: String { case days, list }

    @Environment(PhoneSession.self) private var session
    @AppStorage("calendrier.vue") private var mode = Mode.days
    /// The first of the two days shown.
    @State private var start = LinkWords.calendar.startOfDay(for: Date())
    @State private var events: [LinkEvent] = []
    @State private var keptAt: Date?
    @State private var problem: String?
    @State private var loaded = false
    @State private var shown: LinkEvent?

    private var days: [Date] { (0..<2).compactMap { LinkWords.calendar.date(byAdding: .day, value: $0, to: start) } }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .days:
                    DaysTimeline(days: days, events: events) { shown = $0 }
                        .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                            guard abs(drag.translation.width) > abs(drag.translation.height) * 1.5, abs(drag.translation.width) > 60 else { return }
                            move(drag.translation.width < 0 ? 2 : -2)
                        })
                case .list:
                    EventList(events: events, loaded: loaded, problem: problem) { shown = $0 }
                }
            }
            .navigationTitle(mode == .days ? title : "Calendrier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SettingsButton()
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if mode == .days {
                        Button { move(-2) } label: { Label("Jours précédents", systemImage: "chevron.left") }
                        Button("Aujourd'hui") { start = LinkWords.calendar.startOfDay(for: Date()) }
                            .disabled(LinkWords.calendar.isDateInToday(start))
                        Button { move(2) } label: { Label("Jours suivants", systemImage: "chevron.right") }
                    }
                    Menu {
                        Picker("Vue", selection: $mode) {
                            Label("Deux jours", systemImage: "rectangle.split.2x1").tag(Mode.days)
                            Label("Liste", systemImage: "list.bullet").tag(Mode.list)
                        }
                    } label: {
                        Label("Vue", systemImage: mode == .days ? "rectangle.split.2x1" : "list.bullet")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
            .refreshable { await load() }
            .task(id: "\(mode.rawValue)-\(start.timeIntervalSince1970)") { await load() }
            .sheet(item: $shown) { EventSheet(event: $0).presentationDetents([.medium]) }
        }
        .tint(PhoneStyle.calendar)
    }

    /// « Ven. 20 – sam. 21 nov. », or « Aujourd'hui et demain ».
    private var title: String {
        let calendar = LinkWords.calendar
        if calendar.isDateInToday(start) { return "Aujourd'hui et demain" }
        guard let second = days.last else { return "Calendrier" }
        return "\(LinkWords.dayTitle(start)) – \(LinkWords.dayTitle(second).lowercased())"
    }

    private func move(_ days: Int) {
        withAnimation(.snappy) { start = LinkWords.calendar.date(byAdding: .day, value: days, to: start) ?? start }
    }

    private func load() async {
        let query: [String: String]
        if mode == .days, let end = LinkWords.calendar.date(byAdding: .day, value: 2, to: start) {
            query = ["du": Self.day(start), "au": Self.day(end)]
        } else {
            query = [:]
        }
        do throws(LinkFailure) {
            let fetched = try await session.fetch([LinkEvent].self, LinkAPI.Path.events, query: query)
            events = fetched.value
            keptAt = fetched.keptAt
            problem = nil
        } catch {
            // The Mac does not answer and these two days were never seen: cut in its wide copy, from iCloud (20/11).
            if mode == .days, let end = LinkWords.calendar.date(byAdding: .day, value: 2, to: start), let wide = session.cached([LinkEvent].self, LinkAPI.Path.events) {
                events = wide.value.filter { $0.end > start && $0.start < end }
                keptAt = wide.keptAt
                problem = nil
            } else {
                problem = error.message
            }
        }
        loaded = true
    }

    /// « 2026-11-20 ».
    static func day(_ date: Date) -> String {
        let parts = LinkWords.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// Two days, hour after hour: the events where they fall, side by side when they overlap; the current time in red.
struct DaysTimeline: View {
    let days: [Date]
    let events: [LinkEvent]
    let open: (LinkEvent) -> Void

    static let hourHeight: CGFloat = 60
    static let gutter: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            header
            allDay
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        grid
                        HStack(spacing: 0) {
                            Color.clear.frame(width: Self.gutter)
                            ForEach(days, id: \.self) { day in
                                DayColumn(day: day, events: timed(on: day), hourHeight: Self.hourHeight, open: open)
                                    .frame(maxWidth: .infinity)
                                    .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 0.5) }
                            }
                        }
                        NowLine(days: days, hourHeight: Self.hourHeight, gutter: Self.gutter)
                    }
                    .frame(height: 24 * Self.hourHeight)
                    .padding(.top, 8)
                }
                // A little under the top: the hour's label, drawn above its line, shows whole.
                .onAppear { proxy.scrollTo(Self.firstHour(events: events, days: days), anchor: UnitPoint(x: 0, y: 0.04)) }
            }
        }
    }

    /// The day's title above its column: the weekday, its number; today on the calendar's color.
    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let today = LinkWords.calendar.isDateInToday(day)
                VStack(spacing: 2) {
                    Text(Self.weekday(day)).font(.caption.weight(.semibold)).foregroundStyle(today ? PhoneStyle.calendar : .secondary)
                    Text("\(LinkWords.calendar.component(.day, from: day))")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(today ? .white : .primary)
                        .frame(width: 36, height: 36)
                        .background(today ? PhoneStyle.calendar : .clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    /// The events of whole days, on their color, above the hours.
    @ViewBuilder private var allDay: some View {
        let rows = days.map { day in events.filter { $0.allDay && Self.covers($0, day) } }
        if rows.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("Journée").font(.caption2).foregroundStyle(.secondary).frame(width: Self.gutter)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(spacing: 3) {
                        ForEach(row) { event in
                            Button { open(event) } label: {
                                Text(event.title).font(.caption.weight(.medium)).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Color(hex: event.color ?? "#8E8E93").opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)
        }
    }

    /// The hours, a line each.
    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 4) {
                    Text(hour == 0 ? "" : "\(hour):00").font(.caption2).foregroundStyle(.secondary)
                        .frame(width: Self.gutter - 6, alignment: .trailing).offset(y: -7)
                    Rectangle().fill(.separator).frame(height: 0.5)
                }
                .frame(height: Self.hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func timed(on day: Date) -> [LinkEvent] {
        events.filter { !$0.allDay && Self.covers($0, day) }
    }

    static func covers(_ event: LinkEvent, _ day: Date) -> Bool {
        guard let next = LinkWords.calendar.date(byAdding: .day, value: 1, to: day) else { return false }
        return event.start < next && event.end > day
    }

    /// « ven. »
    static func weekday(_ day: Date) -> String {
        let names = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
        return names[LinkWords.calendar.component(.weekday, from: day) - 1]
    }

    /// Where the view opens: an hour before the first event or now, 7:00 at the earliest of a free morning.
    static func firstHour(events: [LinkEvent], days: [Date]) -> Int {
        let calendar = LinkWords.calendar
        if let first = days.first, calendar.isDateInToday(first) { return max(0, calendar.component(.hour, from: Date()) - 1) }
        let hours = events.filter { !$0.allDay }.map { calendar.component(.hour, from: $0.start) }
        return max(0, min(hours.min() ?? 8, 8) - 1)
    }
}

/// One day's events, placed by their hours; side by side when they overlap.
struct DayColumn: View {
    let day: Date
    let events: [LinkEvent]
    let hourHeight: CGFloat
    let open: (LinkEvent) -> Void

    var body: some View {
        GeometryReader { geometry in
            ForEach(Self.layout(events, day: day)) { placed in
                let width = geometry.size.width / CGFloat(placed.columns)
                EventBlock(event: placed.event, compact: placed.length * hourHeight < 40)
                    .frame(width: max(0, width - 3), height: max(22, placed.length * hourHeight - 2))
                    .offset(x: CGFloat(placed.column) * width + 1.5, y: placed.top * hourHeight + 1)
                    .onTapGesture { open(placed.event) }
            }
        }
    }

    struct Placed: Identifiable {
        var event: LinkEvent
        /// Hours from the day's midnight.
        var top: CGFloat
        var length: CGFloat
        var column: Int
        var columns: Int
        var id: String { event.id }
    }

    /// The events of a day, each in the first column free at its start; the columns of a cluster of overlapping events
    /// share the width.
    static func layout(_ events: [LinkEvent], day: Date) -> [Placed] {
        let end = day.addingTimeInterval(24 * 3_600)
        var placed: [Placed] = []
        var cluster: [Int] = []
        var columnsEnd: [Date] = []
        var clusterEnd = Date.distantPast
        func close() {
            let count = columnsEnd.count
            for index in cluster { placed[index].columns = max(1, count) }
            cluster = []
            columnsEnd = []
        }
        for event in events.sorted(by: { ($0.start, $1.end) < ($1.start, $0.end) }) {
            let start = max(event.start, day), stop = min(max(event.end, start.addingTimeInterval(15 * 60)), end)
            if start >= clusterEnd { close() }
            let column = columnsEnd.firstIndex { $0 <= start } ?? columnsEnd.count
            if column == columnsEnd.count { columnsEnd.append(stop) } else { columnsEnd[column] = stop }
            clusterEnd = max(clusterEnd, stop)
            placed.append(Placed(event: event, top: start.timeIntervalSince(day) / 3_600, length: stop.timeIntervalSince(start) / 3_600,
                                 column: column, columns: 1))
            cluster.append(placed.count - 1)
        }
        close()
        return placed
    }
}

/// An event on its calendar's color: the title, then the hours.
struct EventBlock: View {
    let event: LinkEvent
    let compact: Bool

    var body: some View {
        let color = Color(hex: event.color ?? "#8E8E93")
        HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.caption.weight(.semibold)).lineLimit(compact ? 1 : 2)
                if !compact {
                    Text(LinkWords.timeRange(event.start, event.end)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

/// The current time, a red line across today.
struct NowLine: View {
    let days: [Date]
    let hourHeight: CGFloat
    let gutter: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { geometry in
                if let index = days.firstIndex(where: { LinkWords.calendar.isDate($0, inSameDayAs: context.date) }) {
                    let column = (geometry.size.width - gutter) / CGFloat(days.count)
                    let hours = context.date.timeIntervalSince(days[index]) / 3_600
                    HStack(spacing: 0) {
                        Circle().fill(PhoneStyle.red).frame(width: 8, height: 8)
                        Rectangle().fill(PhoneStyle.red).frame(height: 1.5)
                    }
                    .frame(width: column + 4)
                    .offset(x: gutter + CGFloat(index) * column - 4, y: hours * hourHeight - 4)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The list of the coming fortnight, day by day (the first view, kept).
struct EventList: View {
    let events: [LinkEvent]
    let loaded: Bool
    let problem: String?
    let open: (LinkEvent) -> Void

    private var days: [(day: Date, events: [LinkEvent])] {
        let calendar = LinkWords.calendar
        let today = calendar.startOfDay(for: Date())
        let grouped = Dictionary(grouping: events.filter { $0.end > today }) { calendar.startOfDay(for: max($0.start, today)) }
        return grouped.keys.sorted().map { day in (day, grouped[day]!.sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }) }
    }

    var body: some View {
        List {
            ForEach(days, id: \.day) { day in
                Section(LinkWords.dayTitle(day.day)) {
                    ForEach(day.events) { event in
                        Button { open(event) } label: { EventRow(event: event) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if loaded, days.isEmpty, problem == nil {
                ContentUnavailableView("Aucun rendez-vous", systemImage: "calendar", description: Text("Rien dans les deux semaines à venir."))
            }
        }
    }
}

struct EventRow: View {
    let event: LinkEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: event.color ?? "#8E8E93")).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).fontWeight(.medium)
                Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let meet = event.meet, !event.allDay {
                Link(destination: meet) { Text("Rejoindre").fontWeight(.semibold) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    /// « 9:30 – 10:00 · Studio Nord », « Toute la journée · Atelier ».
    private var meta: String {
        let when = event.allDay ? "Toute la journée" : LinkWords.timeRange(event.start, event.end)
        return ([when] + [event.project, event.location].compactMap { $0 }).joined(separator: " · ")
    }
}

/// An event touched: its day and hours, its project, its place, « Rejoindre ».
struct EventSheet: View {
    let event: LinkEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: event.color ?? "#8E8E93")).frame(width: 6, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.title3.weight(.semibold))
                    Text(LinkWords.dayTitle(event.start) + (event.allDay ? " · toute la journée" : " · " + LinkWords.timeRange(event.start, event.end)))
                        .foregroundStyle(.secondary)
                }
            }
            if let project = event.project { ProjectChip(name: project, color: event.color) }
            if let location = event.location { Label(location, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
            Label(event.account, systemImage: "calendar").font(.footnote).foregroundStyle(.secondary)
            if let meet = event.meet {
                Link(destination: meet) {
                    Label("Rejoindre", systemImage: "video.fill").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .tint(PhoneStyle.calendar)
    }
}
