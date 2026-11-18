import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// Behind « Voir » in « Le point » (step 3, 18/11): what moved without Paul since he last came — by Colin or by an
/// agent — the newest first, each with who made it, when, and « Annuler ». Its title is the point's own sentence.
struct ChangesSheet: View {
    @ObservedObject var colin: ColinLibrary
    var calendar: Calendar = CalendarView.calendar
    @Environment(\.dismiss) private var dismiss

    /// « Depuis hier 19:40 : 3 projets ont bougé. »
    private var title: String {
        colin.briefing.first { $0.hasPrefix("Depuis ") } ?? "Le point"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(verbatim: title).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(colin.briefingChanges.reversed()) { line in
                        ChangeRow(line: line, outcome: colin.changeOutcomes[line.id], calendar: calendar,
                                  byline: ChangeText.byline(line, now: Date(), calendar: calendar)) { colin.undo(line) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.l)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 320, idealHeight: 460)
    }
}
