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
}

/// The title of a card of the Accueil (0.37.0): 17 points, semi-bold, its count in a pill beside it.
struct HomeSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Text(title).font(.system(size: 17, weight: .semibold))
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

/// « Le point » at the head of the day (0.36.0): the date, when it was prepared, and what came since Paul last came,
/// with « Voir ». What is due and the meetings are said by « À faire » and « Aujourd'hui », under it. No card: it sits
/// on the page.
struct BriefingCard: View {
    let sentences: [String]
    let preparedAt: Date
    var calendar: Calendar = CalendarView.calendar
    /// What moved without Paul, to see: « Voir » at the end of what came since.
    var see: (() -> Void)?

    private var since: String? { sentences.first { $0.hasPrefix("Depuis ") } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(BriefingText.today(Date(), calendar: calendar)).font(.title2.weight(.semibold))
                Spacer(minLength: Space.s)
                Text("Le point · \(Briefing.stamp(preparedAt, calendar: calendar))").font(.meta).foregroundStyle(.secondary)
            }
            if let since {
                let part = BriefingText.parts(since)
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(Text(part.label.map { "\($0) : " } ?? "").foregroundStyle(.secondary))\(Text(part.text.prefix(1).lowercased() + part.text.dropFirst()))")
                        .font(.rowBody)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Space.s)
                    if let see { TextButton("Voir", quiet: true, action: see) }
                }
            }
        }
    }
}
