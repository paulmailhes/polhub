import Agenda
import AppKit
import Domain
import Persistence
import ProjectsUI
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

/// Calendrier: the week of every connected Google calendar, an event's details, its project.
struct CalendarView: View {
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    @State private var weekStart = CalendarView.monday(of: .now)
    @State private var selection: String?

    static let hourHeight: CGFloat = 46
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    static func monday(of date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    var days: [Date] { (0..<7).compactMap { Self.calendar.date(byAdding: .day, value: $0, to: weekStart) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if agenda.accounts.isEmpty {
                setup
            } else {
                HStack(spacing: 0) {
                    week
                    if let id = selection, let event = agenda.events.first(where: { $0.id == id }) {
                        Divider()
                        EventInspector(event: event, agenda: agenda, router: router) { selection = nil }
                            .frame(width: 320)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { move(-7) } label: { Image(systemName: "chevron.left") }
            Button("Aujourd'hui") { weekStart = Self.monday(of: .now) }
            Button { move(7) } label: { Image(systemName: "chevron.right") }
            Text(weekTitle).font(.headline)
            Spacer()
            if let failed = agenda.accounts.first(where: { $0.lastError != nil }) {
                Label("\(failed.email) : \(failed.lastError ?? "")", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).lineLimit(1).truncationMode(.tail).frame(maxWidth: 320)
            } else if let last = agenda.accounts.compactMap(\.lastSyncAt).max() {
                Text("À jour à \(last.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary).font(.callout)
            }
            if agenda.syncing { ProgressView().controlSize(.small) }
            Button("Synchroniser") { Task { await agenda.syncAll() } }.disabled(agenda.syncing || agenda.accounts.isEmpty)
            Menu("Comptes") {
                ForEach(agenda.accounts) { account in
                    Menu(account.email) {
                        Button("Déconnecter ce compte", role: .destructive) { Task { await agenda.disconnect(account.email) } }
                    }
                }
                Divider()
                Button("Ajouter un compte Google…") { Task { await agenda.connect() } }.disabled(!agenda.hasGoogleKey)
            }
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var weekTitle: String {
        let format = Date.FormatStyle(date: .long, time: .omitted).locale(Locale(identifier: "fr_FR"))
        guard let last = days.last else { return "" }
        return "Semaine du \(weekStart.formatted(.dateTime.day().locale(Locale(identifier: "fr_FR")))) au \(last.formatted(format))"
    }

    private func move(_ days: Int) {
        weekStart = Self.calendar.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
    }

    // MARK: - No account yet

    private var setup: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Connecte tes agendas Google").font(.title3.bold())
            if agenda.hasGoogleKey {
                Text("Polhub lit tes rendez-vous en lecture seule : les invités deviennent des contacts, rangés dans les projets de leurs rendez-vous.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
                Button("Ajouter un compte Google…") { Task { await agenda.connect() } }.buttonStyle(.borderedProminent)
            } else {
                Text("La clé Google n'est pas encore en place : lance « configurer-google.command », dans le dossier scripts de Polhub, puis reviens ici.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 460)
            }
            if let message = agenda.message { Text(message).font(.callout).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The week

    private var week: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 48, height: 0)
                ForEach(days, id: \.self) { day in
                    let today = Self.calendar.isDateInToday(day)
                    Text(day.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_FR"))))
                        .font(.callout.weight(today ? .bold : .regular))
                        .foregroundStyle(today ? Color.accentColor : Color.primary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            allDayRow
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(width: 48, height: Self.hourHeight, alignment: .topTrailing).padding(.trailing, 4).id(hour)
                            }
                        }
                        ForEach(days, id: \.self) { day in
                            dayColumn(day)
                        }
                    }
                }
                .onAppear { scroll.scrollTo(8, anchor: .top) }
            }
        }
    }

    private var allDayRow: some View {
        let allDay = agenda.events.filter(\.allDay)
        return HStack(spacing: 0) {
            Color.clear.frame(width: 48, height: 0)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 2) {
                    ForEach(allDay.filter { $0.startAt <= day && $0.endAt > day }) { event in
                        Text(event.title).font(.caption).lineLimit(1).padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
                            .background(color(event).opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                            .onTapGesture { selection = event.id }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 2)
            }
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let start = Self.calendar.startOfDay(for: day)
        let end = Self.calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let events = agenda.events.filter { !$0.allDay && $0.startAt < end && $0.endAt > start }
        let slots = DayLayout.place(events.map { (max($0.startAt, start), min($0.endAt, end)) })
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle().fill(Color.secondary.opacity(0.12)).frame(height: 1).frame(maxHeight: Self.hourHeight, alignment: .top)
                    }
                }
                if Self.calendar.isDateInToday(day) {
                    Rectangle().fill(Color.red).frame(height: 1.5).offset(y: offset(Date(), from: start))
                }
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    let slot = slots[index]
                    let width = geometry.size.width / CGFloat(slot.columns)
                    let top = offset(max(event.startAt, start), from: start)
                    let height = max(18, offset(min(event.endAt, end), from: start) - top)
                    eventBlock(event, height: height)
                        .frame(width: width - 3, height: height - 2)
                        .offset(x: CGFloat(slot.column) * width + 1, y: top + 1)
                }
            }
        }
        .frame(height: Self.hourHeight * 24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1) }
    }

    private func offset(_ date: Date, from start: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(start) / 3_600) * Self.hourHeight
    }

    private func eventBlock(_ event: CalendarEventRow, height: CGFloat) -> some View {
        let declined = event.attendees.first(where: \.isSelf)?.response == "declined"
        return VStack(alignment: .leading, spacing: 1) {
            Text(event.title).font(.caption.weight(.semibold)).lineLimit(height > 40 ? 2 : 1)
            if height > 34 {
                Text(event.startAt.formatted(date: .omitted, time: .shortened)
                     + (project(event).map { " · \($0.name)" } ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color(event).opacity(selection == event.id ? 0.4 : 0.2), in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(color(event)).frame(width: 3) }
        .opacity(declined ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture { selection = event.id }
        .help(event.title)
    }

    private func project(_ event: CalendarEventRow) -> ProjectRow? {
        event.projectID.flatMap { id in agenda.projects.first { $0.id == id } }
    }

    private func color(_ event: CalendarEventRow) -> Color {
        guard let project = project(event) else { return .gray }
        return ProjectViews.cardHex(project.color).map(Color.init(hex:)) ?? .accentColor
    }
}

/// One event: when, the Meet, its project (and why), its recording, its guests.
struct EventInspector: View {
    let event: CalendarEventRow
    @ObservedObject var agenda: AgendaLibrary
    @ObservedObject var router: WindowRouter
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(event.title).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                Text(when).foregroundStyle(.secondary)
                if let code = event.meetCode, let url = URL(string: "https://meet.google.com/\(code)") {
                    Link(destination: url) { Label("Google Meet · \(code)", systemImage: "video") }
                }
                if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin").foregroundStyle(.secondary) }

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
                if let reason { Text(reason).font(.caption).foregroundStyle(.secondary) }

                if let meetingID = event.meetingID {
                    Button { router.open(meetingID: meetingID, at: nil) } label: { Label("Ouvrir la réunion enregistrée", systemImage: "waveform") }
                }

                if !event.guests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Invités (\(event.guests.count))").font(.headline)
                        ForEach(event.guests, id: \.email) { guest in
                            let contact = agenda.contact(email: guest.email)
                            Button {
                                if let contact { router.openContact(contact.id) }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(contact?.name ?? Linker.name(for: guest)).foregroundStyle(.primary)
                                    Text([contact?.company, guest.email].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let link = event.htmlLink.flatMap(URL.init(string:)) {
                    Link("Ouvrir dans Google Agenda", destination: link).font(.callout)
                }
                Text(event.account).font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var when: String {
        let locale = Locale(identifier: "fr_FR")
        if event.allDay { return event.startAt.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)) + ", toute la journée" }
        return event.startAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(locale))
            + " – " + event.endAt.formatted(.dateTime.hour().minute().locale(locale))
    }

    private var reason: String? {
        switch event.projectOrigin {
        case .paul?: "Rangé par toi."
        case .reunion?: "D'après la réunion enregistrée."
        case .serie?: "D'après les autres rendez-vous de la série."
        case .invites?: "D'après les projets des invités."
        case .titre?: "D'après le titre."
        case nil: event.projectID == nil ? "Pas de projet trouvé : choisis-le, les invités suivront." : nil
        }
    }
}
