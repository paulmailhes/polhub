import Colin
import HubDesign
import SwiftUI

/// The words of « Le point ».
enum BriefingText {
    /// « Mercredi 18 novembre », « Dimanche 1er novembre » (lot 10, 20/11: written by `Words`, no formatter of its own).
    static func today(_ date: Date, calendar: Calendar) -> String {
        Words.capitalizedFirst(Words.fullDate(date, now: date, calendar: calendar))
    }

    /// The line under the date (lot 5, 19/11): what came since Paul last came, on one line — « Depuis hier 19:40 · 1 mail
    /// de client, 2 projets ont bougé ». Nothing when nothing came. Found by its kind, its label and text apart (lot 10,
    /// 20/11: by its first word, and cut at its « : »).
    static func since(_ lines: [Briefing.Line]) -> String? {
        guard let line = lines.first(where: { $0.kind == .since }) else { return nil }
        var text = line.text
        if text.hasSuffix(".") { text.removeLast() }
        return "\(line.label) · \(text)"
    }

    /// When « Le point » was prepared, under the pointer (lot 5, 19/11): « Le point · aujourd'hui 18:55 » (lot 10, 20/11:
    /// the day and its hour by `Words.moment`).
    static func prepared(_ date: Date, now: Date, calendar: Calendar) -> String {
        "Le point · " + Words.moment(date, now: now, calendar: calendar)
    }
}

/// The title of a card of the Accueil (0.37.0): 17 points, semi-bold, its count in a pill beside it.
struct HomeSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            // 17 points: the title of a card (lot 5, 19/11: a style, no longer a size written by hand).
            Text(title).font(.title2.weight(.semibold))
            if let count {
                // The number as French writes it (lot 10, 20/11: `Words.number`).
                Text(Words.number(count))
                    .font(.meta.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(Surface.raised, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

/// The head of the day (lot 5, 19/11): the date as the page's title, in 26 points, and under it one line of what came
/// since Paul last came, « Voir › » right after it; when « Le point » was prepared is said under the pointer. The date
/// shows always, the line only when something came. What is due and the meetings are said by the cards under it.
struct DayHeader: View {
    let sentences: [Briefing.Line]
    let preparedAt: Date?
    var calendar: Calendar = CalendarView.calendar
    /// What moved without Paul, to see: « Voir › » at the end of the line.
    var see: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            // The date turns at midnight with the page open.
            TimelineView(.everyMinute) { context in
                PageHeader(BriefingText.today(context.date, calendar: calendar))
            }
            if let since = BriefingText.since(sentences) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(since).font(.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let see { TextButton("Voir ›", quiet: true, action: see).fixedSize() }
                }
                .help(preparedAt.map { BriefingText.prepared($0, now: Date(), calendar: calendar) } ?? "")
            }
        }
    }
}
