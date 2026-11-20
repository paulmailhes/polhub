import Agenda
import AppKit
import Domain
import Persistence
import ProjectsUI
import PolhubDesign
import SwiftUI

/// Where the overlapping events of a day sit: a column, and how many columns their group shares.
enum DayLayout {
    static func place(_ items: [(start: Date, end: Date)]) -> [(column: Int, columns: Int)] {
        let order = items.indices.sorted { items[$0].start < items[$1].start || (items[$0].start == items[$1].start && items[$0].end > items[$1].end) }
        var result = Array(repeating: (column: 0, columns: 1), count: items.count)
        var group: [Int] = []
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast
        func close() {
            for index in group { result[index].columns = columnEnds.count }
            group = []
            columnEnds = []
        }
        for index in order {
            let item = items[index]
            if item.start >= groupEnd { close() }
            if let free = columnEnds.firstIndex(where: { $0 <= item.start }) {
                columnEnds[free] = item.end
                result[index].column = free
            } else {
                columnEnds.append(item.end)
                result[index].column = columnEnds.count - 1
            }
            group.append(index)
            groupEnd = max(groupEnd == .distantPast ? item.end : groupEnd, item.end)
        }
        close()
        return result
    }
}

/// Calendrier: the week of every connected Google calendar, each account in its color; a click opens the
/// event, from which Paul joins it with the right account (14/11).
struct CalendarView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @State private var weekStart = CalendarView.monday(of: .now)
    @State private var selection: String?
    /// The day of the block clicked: an event over several days opens one card, there (review of 14/11).
    @State private var selectedDay: Date?
    /// The editor of an event, new or existing (14/11).
    @State private var editor: EditorRequest?
    /// Where the hours' grid is scrolled.
    @State private var gridPosition = ScrollPosition(edge: .top)

    static let hourHeight: CGFloat = 48
    static let gutter: CGFloat = 52
    /// The room above midnight's line, at the top of the grid.
    static let gridTop: CGFloat = Space.s
    /// How far an hour's label rises over its line, so that its middle sits on it.
    static let labelRise: CGFloat = 6

    /// Where the grid opens, for the hour of Réglages › Calendrier: a margin above that hour's label, so that it is read
    /// whole (lot 8, 19/11: the grid opened on the line itself, and « 08 h » was cut in half at the top).
    static func openingOffset(hour: Int) -> CGFloat {
        let line = gridTop + CGFloat(min(max(0, hour), 23)) * hourHeight
        return max(0, line - labelRise - Space.s)
    }
    /// French and Paul's calendar, fixed once by `Words` (lot 10, 20/11): the Accueil reads them here too.
    static let locale = Words.locale
    static var calendar: Calendar { Words.calendar }

    static func monday(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    @AppStorage(Preferences.Key.showWeekend) private var showWeekend = true
    @AppStorage(Preferences.Key.dayStartHour) private var dayStartHour = Preferences.Default.dayStartHour

    /// Monday to Sunday, or to Friday (Réglages › Calendrier).
    var days: [Date] { (0..<(showWeekend ? 7 : 5)).compactMap { Self.calendar.date(byAdding: .day, value: $0, to: weekStart) } }

    var body: some View {
        Group {
            if agenda.accounts.isEmpty {
                setup
            } else {
                // No legend: the accounts and their colors live in Réglages › Calendrier (Paul, 14/11).
                week
            }
        }
        .windowTitle("Calendrier", subtitle: weekTitle)
        .toolbar { toolbar }
        .onAppear(perform: openAsked)
        .sheet(item: $editor) { request in EventEditor(agenda: agenda, request: request) }
        .onChange(of: router.eventSelection) { _, _ in openAsked() }
        // « Nouveau rendez-vous », from the toolbar or from « Coup d'œil » (15/11): once the page is on screen.
        .task(id: router.newEventRequest) { openNewEvent() }
    }

    /// A new event asked through the router: its editor, if a calendar can take it. The request is used either way:
    /// it never opens an editor later, when an account is connected.
    private func openNewEvent() {
        guard router.newEventRequest != nil else { return }
        router.newEventRequest = nil
        guard !agenda.accounts.isEmpty, editor == nil else { return }
        editor = EditorRequest()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // An icon alone says its gesture, the same words in its bubble and to VoiceOver (lot 10, 20/11).
        ToolbarItemGroup(placement: .navigation) {
            Button { move(-7) } label: { Label("Aller à la semaine précédente", systemImage: "chevron.left") }
                .help("Aller à la semaine précédente")
            Button("Aujourd'hui") { weekStart = Self.monday(of: .now) }
            Button { move(7) } label: { Label("Aller à la semaine suivante", systemImage: "chevron.right") }
                .help("Aller à la semaine suivante")
        }
        ToolbarItem(placement: .primaryAction) {
            SyncStatus(agenda: agenda)
        }
        ToolbarItem(placement: .primaryAction) {
            // ⌘N makes one on this page (`WindowKeys`); the double click on the grid is found alone.
            Button { router.newEvent() } label: { Label("Créer un rendez-vous", systemImage: "plus") }
                .help(Words.help("Créer un rendez-vous", .command("n")))
                .disabled(agenda.accounts.isEmpty)
        }
    }

    /// « Novembre 2026 », by `Words` (lot 10, 20/11).
    private var weekTitle: String {
        Words.capitalizedFirst(Words.month(weekStart, year: true, calendar: Self.calendar))
    }

    private func move(_ days: Int) {
        weekStart = Self.calendar.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
    }

    /// What the copy does not hold of the week shown, as the agents are told (`AgendaDesk.gaps`): an empty week past it is
    /// not a free one (audit of 19/11). The day by `Words`, its year when it is not the week's (lot 10, 20/11).
    static func copyNotice(weekStart: Date, days: Int, accounts: [GoogleAccountRow]) -> String? {
        guard let covered = CalendarWindow.covered(by: accounts),
              let end = calendar.date(byAdding: .day, value: days, to: weekStart), end > covered.to else { return nil }
        let last = Words.fullDate(covered.to, now: weekStart, calendar: calendar)
        return "Polhub lit tes agendas jusqu'au \(last) : au-delà, regarde Google Agenda."
    }

    /// Accueil asked for an event: its week, and its card open.
    private func openAsked() {
        guard let id = router.eventSelection else { return }
        router.eventSelection = nil
        guard let event = agenda.shown.first(where: { $0.id == id || $0.eventID == id }) else { return }
        weekStart = Self.monday(of: event.startAt)
        selection = event.id
        selectedDay = Self.calendar.startOfDay(for: event.startAt)
    }

    // MARK: - No account yet

    private var setup: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "calendar").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            // Without the key, a clear title, then what to do (lot 10, 20/11).
            Text(agenda.hasGoogleKey ? "Connecte tes agendas Google" : "Il manque la clé Google").font(.title2.bold())
            if agenda.hasGoogleKey {
                Text(Words.typeset("Polhub lit tes rendez-vous, et crée ou modifie ceux que tu lui demandes : les invités deviennent des contacts, rangés dans les projets de leurs rendez-vous."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
                // « Connecter » a Google account, never « Ajouter » (lot 10, 20/11).
                Button("Connecter un compte Google…") { Task { await agenda.connect() } }
                    .buttonStyle(.primary).controlSize(.large)
            } else {
                Text(Words.typeset("Lance « configurer-google.command », dans le dossier scripts de Polhub, puis reviens ici."))
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            }
            if let message = agenda.message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The week

    private var week: some View {
        VStack(spacing: 0) {
            dayHeader
            // Past what Polhub reads of the agendas, the week says so (audit of 19/11).
            if let notice = Self.copyNotice(weekStart: weekStart, days: days.count, accounts: agenda.accounts) {
                Label(notice, systemImage: "info.circle")
                    .font(.tag).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Space.s)
            }
            allDayRow
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    hourLabels
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(days, id: \.self) { day in dayColumn(day) }
                    }
                    // Under the events: the hours and the days, one pixel each (19/11).
                    .background { WeekGridLines(days: days.count, hourHeight: Self.hourHeight) }
                }
                .padding(.top, Self.gridTop)
            }
            .scrollPosition($gridPosition)
            // The hour of Réglages › Calendrier near the top of the grid, its label whole, once it is laid out (14/11: an
            // anchor put that hour at the same fraction of the screen; lot 8, 19/11: the hour's view at the top cut its
            // label, which rises over the line).
            .task(id: dayStartHour) {
                try? await Task.sleep(for: .milliseconds(80))
                gridPosition.scrollTo(y: Self.openingOffset(hour: dayStartHour))
            }
        }
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let today = Self.calendar.isDateInToday(day)
                // Today at the app's accent, ink; its number in the accent's opposite (design system v2, 19/11). The day's
                // words by `Words` (lot 10, 20/11).
                HStack(spacing: 6) {
                    Text(Words.weekday(day, short: true, calendar: Self.calendar).uppercased())
                        .font(.caption.weight(.medium)).foregroundStyle(today ? Tint.accent : .secondary)
                    Text(Words.number(Self.calendar.component(.day, from: day)))
                        .font(.title3.weight(today ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(today ? Tint.onAccent.color : .primary)
                        .frame(minWidth: 30, minHeight: 30)
                        .background { if today { Circle().fill(Tint.accent) } }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Space.s)
    }

    private var allDayRow: some View {
        let allDay = agenda.shown.filter(\.allDay)
        return HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: Self.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(allDay.filter { $0.startAt <= day && $0.endAt > day }) { event in
                        let color = agenda.color(for: event.account)
                        Button {
                            selection = event.id
                            selectedDay = day
                        } label: {
                            Text(event.title).font(.caption.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        // Its color a shade stronger under the pointer, pressed a touch smaller (15/11).
                        .buttonStyle(HoverButtonStyle(.rounded, fill: color.opacity(0.14)))
                        .popover(isPresented: shows(event, on: day), arrowEdge: .bottom) { popover(event) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
            }
        }
        .padding(.bottom, Space.xs)
    }

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                // « 8 h », never « 08 h » (lot 10, 20/11).
                Text(hour == 0 ? "" : Words.hour(hour))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: Self.gutter - Space.s, height: Self.hourHeight, alignment: .topTrailing)
                    .offset(y: -Self.labelRise)
                    .padding(.trailing, Space.s)
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let start = Self.calendar.startOfDay(for: day)
        let end = Self.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let events = agenda.shown.filter { !$0.allDay && $0.startAt < end && $0.endAt > start }
        let slots = DayLayout.place(events.map { (max($0.startAt, start), min($0.endAt, end)) })
        let weekend = Self.calendar.isDateInWeekend(day)
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // The lines are drawn once for the week (`WeekGridLines`); here, only where a double click lands.
                Color.clear
                    .contentShape(Rectangle())
                // A double click on the grid: a new event at that half hour.
                .onTapGesture(count: 2, coordinateSpace: .local) { point in
                    let halfHours = max(0, min(47, Int(point.y / (Self.hourHeight / 2))))
                    editor = EditorRequest(start: Self.calendar.date(byAdding: .minute, value: halfHours * 30, to: start))
                }
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    let slot = slots[index]
                    let width = geometry.size.width / CGFloat(slot.columns)
                    let top = offset(max(event.startAt, start), from: start)
                    let height = max(20, offset(min(event.endAt, end), from: start) - top)
                    eventBlock(event, height: height - 2, day: start)
                        .frame(width: max(0, width - 4), height: height - 2)
                        .popover(isPresented: shows(event, on: start), arrowEdge: .trailing) { popover(event) }
                        .padding(.leading, CGFloat(slot.column) * width + 2)
                        .padding(.top, top + 1)
                }
                if Self.calendar.isDateInToday(day) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        NowLine().offset(y: offset(context.date, from: start) - 4)
                    }
                }
            }
        }
        .frame(height: Self.hourHeight * 24)
        .frame(maxWidth: .infinity)
        .background(weekend ? Color.secondary.opacity(0.04) : .clear)
    }

    private func offset(_ date: Date, from start: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(start) / 3_600) * Self.hourHeight
    }

    private func shows(_ event: CalendarEventRow, on day: Date) -> Binding<Bool> {
        Binding(get: { selection == event.id && selectedDay == day },
                set: { if !$0, selection == event.id, selectedDay == day { selection = nil } })
    }

    private func popover(_ event: CalendarEventRow) -> some View {
        EventPopover(event: event, agenda: agenda, router: router, edit: {
            selection = nil
            editor = EditorRequest(event: event)
        }) { selection = nil }
    }

    private func eventBlock(_ event: CalendarEventRow, height: CGFloat, day: Date) -> some View {
        let declined = event.attendees.first(where: \.isSelf)?.response == "declined"
        let color = agenda.color(for: event.account)
        let selected = selection == event.id
        return Button {
            selection = event.id
            selectedDay = day
        } label: {
            eventLabel(event, height: height, color: color, selected: selected)
        }
        // Its color a shade stronger under the pointer, pressed a touch smaller (15/11).
        .buttonStyle(HoverButtonStyle(.rounded, fill: color.opacity(0.14)))
        .opacity(declined ? 0.45 : 1)
        .help(event.title)
    }

    private func eventLabel(_ event: CalendarEventRow, height: CGFloat, color: Color, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(event.title).font(.caption.weight(.semibold)).lineLimit(height > 44 ? 2 : 1)
                Spacer(minLength: 0)
                if event.meetingID != nil { Image(systemName: "waveform").font(.caption2).foregroundStyle(color) }
            }
            if height > 34 {
                // « 9:30 », by `Words` (lot 10, 20/11).
                Text(Words.time(event.startAt, calendar: CalendarView.calendar) + (project(event).map { " · \($0.name)" } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.leading, Space.s)
        .padding(.trailing, Space.xs)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
        .background(color.opacity(selected ? 0.38 : 0.2), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(alignment: .leading) { Capsule().fill(color).frame(width: 3).padding(.vertical, 3).padding(.leading, 2) }
        .overlay { if selected { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(color, lineWidth: 1) } }
        .contentShape(Rectangle())
    }

    private func project(_ event: CalendarEventRow) -> ProjectRow? {
        event.projectID.flatMap { id in agenda.projects.first { $0.id == id } }
    }
}

/// The line of the current time, with its dot, in the color of « now » (design system v2, 19/11: no longer the
/// system's red, which says « late » and « recording »).
struct NowLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Tint.attention).frame(width: 8, height: 8)
            Rectangle().fill(Tint.attention).frame(height: 1.5)
        }
        .frame(height: 8)
        .offset(x: -4)
        .allowsHitTesting(false)
    }
}

/// When the calendars were last read, an error, and « Actualiser » (lot 10, 20/11: « Synchroniser » before; one verb
/// to read Google again, for the agendas, the mails and the logos).
struct SyncStatus: View {
    @ObservedObject var agenda: AgendaLibrary

    var body: some View {
        HStack(spacing: Space.s) {
            if agenda.syncing {
                ProgressView().controlSize(.small)
            } else if let last = agenda.accounts.compactMap(\.lastSyncAt).max() {
                Text("À jour à " + Words.time(last)).font(.callout).foregroundStyle(.secondary)
            }
            Button { Task { await agenda.syncAll() } } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                .disabled(agenda.syncing || agenda.accounts.isEmpty)
                .help("Actualiser les agendas")
        }
    }
}

/// One event, in a popover: when, « Rejoindre » with its account, its project (and why), its recording,
/// its guests.
struct EventPopover: View {
    let event: CalendarEventRow
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    /// Opens the editor (only for the events Paul organizes).
    var edit: (() -> Void)?
    let close: () -> Void

    private var color: Color { agenda.color(for: event.account) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.s) {
                Capsule().fill(color).frame(width: 4).frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(event.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    // The range of hours kept whole by `Words.typeset` (lot 10, 20/11).
                    Text(Words.typeset(when)).foregroundStyle(.secondary)
                    Text("\(AccountStyle.label(for: event.account)) · \(event.account)").font(.meta).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if EventCopies.canEdit(event), let edit {
                    Button("Modifier", action: edit).buttonStyle(.secondary).controlSize(.small)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !EventCopies.canEdit(event), let organizer = event.organizer {
                Text("Invitation \(Words.of(agenda.contact(email: organizer)?.name ?? organizer)) : seul l'organisateur la modifie.")
                    .font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if event.meetCode != nil {
                Button {
                    agenda.join(event)
                    close()
                } label: {
                    Label("Rejoindre", systemImage: "video.fill").frame(maxWidth: .infinity)
                }
                // Glass in a popover, at the app's accent whatever the account: the account's color stays in its
                // stripe (design system v2, 19/11). The words of every « Rejoindre », and ↩, which joins here (lot 10, 20/11).
                .buttonStyle(.primary)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .help(Words.help(Words.joinHelp(account: AccountStyle.label(for: event.account)), .return))
            }
            if let meetingID = event.meetingID {
                Button {
                    close()
                    router.open(meetingID: meetingID, at: nil)
                } label: {
                    // A meeting is what Polhub recorded: « Ouvrir la réunion » (lot 10, 20/11).
                    Label("Ouvrir la réunion", systemImage: "waveform").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
            }
            if let location = event.location, !location.isEmpty, !location.hasPrefix("http") {
                Label(location, systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Picker("Projet", selection: Binding(
                    get: { event.projectID },
                    set: { id in Task { await agenda.setProject(event, projectID: id) } }
                )) {
                    Text("Aucun").tag(UUID?.none)
                    ForEach(agenda.projects.filter { $0.status != .termine || $0.id == event.projectID }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                // French typography, laid at display (lot 10, 20/11).
                if let reason { Text(Words.typeset(reason)).font(.meta).foregroundStyle(.secondary) }
                // The project leads to itself, as from a contact's page (lot 4, 19/11).
                if let id = event.projectID, agenda.projects.contains(where: { $0.id == id }) {
                    TextButton("Ouvrir le projet") {
                        close()
                        router.openProject(id)
                    }
                }
            }

            // Who is a contact, who is in the event's project, and a click to change it, here (15/11).
            EventGuests(event: event, agenda: agenda, router: router, close: close)
            if let link = event.htmlLink.flatMap(URL.init(string:)) {
                TextButton("Ouvrir dans Google Agenda") { NSWorkspace.shared.open(link) }
            }
        }
        .padding(Space.l)
        .frame(width: 320, alignment: .leading)
    }

    /// « Jeudi 19 novembre, 9:30 – 10:00 », « Jeudi 19 novembre, toute la journée »: by `Words`, the year when it is not
    /// this one's (lot 10, 20/11).
    private var when: String {
        let day = Words.capitalizedFirst(Words.fullDate(event.startAt, now: Date(), calendar: CalendarView.calendar))
        if event.allDay { return day + ", " + Words.allDay }
        return day + ", " + Words.timeRange(from: event.startAt, to: event.endAt, calendar: CalendarView.calendar)
    }

    private var reason: String? {
        switch event.projectOrigin {
        case .paul?: event.projectID == nil ? "Sorti de tout projet par toi." : "Rangé par toi."
        // A meeting is what Polhub recorded (lot 10, 20/11).
        case .reunion?: "D'après la réunion."
        case .serie?: "D'après les autres rendez-vous de la série."
        case .invites?: "D'après les projets des invités."
        case .titre?: "D'après le titre."
        case nil: event.projectID == nil ? "Pas de projet trouvé : choisis-le, les invités suivront." : nil
        }
    }
}

/// Where a line one device pixel wide is drawn so that it covers exactly one pixel (19/11): half a point, or a line
/// between two pixels, is spread over both and fades away on a screen that is not Retina.
enum PixelGrid {
    /// The middle of the pixel that holds `x`, at the screen's scale.
    static func line(at x: CGFloat, scale: CGFloat) -> CGFloat {
        (floor(x * scale) + 0.5) / scale
    }
}

/// The week's grid, drawn once (19/11): a line at each hour, one between the days, the system's separator color, one
/// device pixel wide and set on a pixel, so it stays as visible at any width of the window.
struct WeekGridLines: View {
    let days: Int
    let hourHeight: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        Canvas { context, size in
            var path = Path()
            for hour in 0..<24 {
                let y = PixelGrid.line(at: CGFloat(hour) * hourHeight, scale: scale)
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            for day in 0..<max(days, 1) {
                let x = PixelGrid.line(at: size.width * CGFloat(day) / CGFloat(max(days, 1)), scale: scale)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1 / scale)
        }
        .allowsHitTesting(false)
    }
}
