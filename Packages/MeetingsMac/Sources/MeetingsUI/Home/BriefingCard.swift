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

/// A title of the Accueil's columns: 15 points, its count beside it (the Accueil's pass, 18/11).
struct HomeSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let count { Text("\(count)").font(.meta.monospacedDigit()).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
    }
}

/// « Le point » at the head of the day (the Accueil's pass, 18/11): the date, a few figures — a click puts its question
/// in Colin's bar — and what came since Paul last came, with « Voir ». No card: it sits on the page.
struct BriefingCard: View {
    let sentences: [String]
    let preparedAt: Date
    var figures: Briefing.Figures?
    var calendar: Calendar = CalendarView.calendar
    /// What moved without Paul, to see: « Voir » at the end of what came since.
    var see: (() -> Void)?
    /// A figure clicked: its question, in the bar.
    var ask: ((String) -> Void)?

    private var since: String? { sentences.first { $0.hasPrefix("Depuis ") } }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(BriefingText.today(Date(), calendar: calendar)).font(.title2.weight(.semibold))
                Spacer(minLength: Space.s)
                Text("Le point · \(Briefing.stamp(preparedAt, calendar: calendar))").font(.meta).foregroundStyle(.secondary)
            }
            if let figures, !figures.tiles.isEmpty {
                HStack(spacing: Space.s) {
                    ForEach(figures.tiles, id: \.tile) { figure in tile(figure, figures: figures) }
                }
            } else {
                // Nothing to count: the week said in words.
                ForEach(sentences.filter { !$0.hasPrefix("Depuis ") }, id: \.self) { sentence in
                    Text(sentence).font(.rowBody).foregroundStyle(.secondary)
                }
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

    private func tile(_ figure: Briefing.Figure, figures: Briefing.Figures) -> some View {
        let names = figure.tile == .due ? figures.due : figure.tile == .yours ? figures.yours : []
        return Button { ask?(Briefing.question(for: figure.tile)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(figure.count)").font(.title2.weight(.semibold).monospacedDigit())
                Text(Briefing.label(figure.tile, count: figure.count)).font(.meta).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.hover(.rounded))
        .help(names.isEmpty ? Briefing.question(for: figure.tile) : names.joined(separator: ", "))
    }
}
