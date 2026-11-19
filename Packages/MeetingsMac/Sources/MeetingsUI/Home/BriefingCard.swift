import Colin
import PolhubDesign
import SwiftUI

/// The words of « Le point ».
enum BriefingText {
    /// A sentence of the point: what it speaks of, then what it says.
    struct Part: Equatable {
        var label: String?
        var text: String
    }

    /// « Cette semaine : aucun rendez-vous. » → « Cette semaine », « Aucun rendez-vous. ». The colon that ends the
    /// label has a space on each side: the one of an hour (« 19:40 ») has none.
    static func parts(_ sentence: String) -> Part {
        guard let cut = sentence.range(of: " : ") else { return Part(label: nil, text: sentence) }
        let text = String(sentence[cut.upperBound...])
        return Part(label: String(sentence[..<cut.lowerBound]), text: text.prefix(1).uppercased() + text.dropFirst())
    }

    /// « Mercredi 18 novembre ».
    static func today(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM"
        let said = formatter.string(from: date)
        return said.prefix(1).uppercased() + said.dropFirst()
    }

    /// The line under the date (lot 5, 19/11): what came since Paul last came, on one line — « Depuis hier 19:40 · 1 mail
    /// de client, 2 projets ont bougé ». Nothing when nothing came.
    static func since(_ sentences: [String]) -> String? {
        guard let sentence = sentences.first(where: { $0.hasPrefix("Depuis ") }) else { return nil }
        let part = parts(sentence)
        var text = part.text.prefix(1).lowercased() + part.text.dropFirst()
        if text.hasSuffix(".") { text.removeLast() }
        return part.label.map { "\($0) · \(text)" } ?? text
    }

    /// When « Le point » was prepared, under the pointer (lot 5, 19/11): « Le point · aujourd'hui 18:55 ».
    static func prepared(_ date: Date, now: Date, calendar: Calendar) -> String {
        "Le point · \(Briefing.dayLabel(date, now: now, calendar: calendar))"
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
                Text("\(count)")
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
    let sentences: [String]
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
