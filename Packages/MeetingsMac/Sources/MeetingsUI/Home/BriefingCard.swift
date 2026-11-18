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
}

/// « Le point · mardi 9:04 » (18/11): four sentences at most, as they stood when Paul came back. What each speaks
/// of on the left, what it says on the right.
struct BriefingCard: View {
    let sentences: [String]
    let preparedAt: Date
    var calendar: Calendar = CalendarView.calendar

    var body: some View {
        Card(padding: Space.l + Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("Le point").font(.headline)
                Text(Briefing.stamp(preparedAt, calendar: calendar)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
                ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                    let part = BriefingText.parts(sentence)
                    GridRow {
                        if let label = part.label {
                            // The label keeps its line; what it says takes the rest of the card, and wraps there.
                            Text(label).font(.rowBody).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                            Text(part.text).font(.rowTitle).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(part.text).font(.rowTitle).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                .gridCellColumns(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
