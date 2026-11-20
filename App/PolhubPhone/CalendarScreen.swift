import PolhubLink
import SwiftUI

/// Calendrier: from yesterday to two weeks ahead, day by day; « Rejoindre » opens the Meet (20/11).
struct CalendarScreen: View {
    @Environment(PhoneSession.self) private var session
    @State private var events: [LinkEvent] = []
    @State private var keptAt: Date?
    @State private var problem: String?
    @State private var loaded = false

    /// Today and after first; yesterday is not shown.
    private var days: [(day: Date, events: [LinkEvent])] {
        let calendar = LinkWords.calendar
        let today = calendar.startOfDay(for: Date())
        let grouped = Dictionary(grouping: events.filter { $0.end > today }) { calendar.startOfDay(for: max($0.start, today)) }
        return grouped.keys.sorted().map { day in (day, grouped[day]!.sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(days, id: \.day) { day in
                    Section(LinkWords.dayTitle(day.day)) {
                        ForEach(day.events) { EventRow(event: $0) }
                    }
                }
            }
            .overlay {
                if loaded, days.isEmpty, problem == nil {
                    ContentUnavailableView("Aucun rendez-vous", systemImage: "calendar", description: Text("Rien dans les deux semaines à venir."))
                }
            }
            .navigationTitle("Calendrier")
            .safeAreaInset(edge: .top, spacing: 0) { StateLine(keptAt: keptAt, problem: problem) }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        do throws(LinkFailure) {
            let fetched = try await session.fetch([LinkEvent].self, LinkAPI.Path.events)
            events = fetched.value
            keptAt = fetched.keptAt
            problem = nil
        } catch {
            problem = error.message
        }
        loaded = true
    }
}

struct EventRow: View {
    let event: LinkEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Color(hex: event.color ?? "#8E8E93")).frame(width: 8, height: 8).padding(.top, 6)
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

/// Réglages: which Mac this iPhone reads, and how to unpair it.
struct PhoneSettingsScreen: View {
    @Environment(PhoneSession.self) private var session
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    LabeledContent("Adresse", value: session.connection?.address.host() ?? "—")
                    LabeledContent("Polhub sur le Mac", value: session.status?.appVersion ?? "—")
                    LabeledContent("Cet iPhone", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
                Section {
                    Button("Délier cet iPhone", role: .destructive) { confirming = true }
                } footer: {
                    Text("L'iPhone oublie le Mac et efface sa copie. Pour le relier de nouveau, scanne un nouveau code sur le Mac.")
                }
            }
            .navigationTitle("Réglages")
            .task { await session.refreshStatus() }
            .confirmationDialog("Délier cet iPhone ?", isPresented: $confirming) {
                Button("Délier", role: .destructive) { session.unpair() }
            }
        }
    }
}
