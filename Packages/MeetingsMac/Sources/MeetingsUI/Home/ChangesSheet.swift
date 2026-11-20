import Colin
import Persistence
import PolhubDesign
import SwiftUI

/// Behind « Voir » in « Le point » (step 3, 18/11; the Accueil's pass, 18/11): what came since Paul last came — the
/// threads where a client wrote, with « Ouvrir », then what moved without him, by Colin or by an agent, each with who
/// made it, when, and « Annuler ». Its title is the point's own sentence.
struct ChangesSheet: View {
    @ObservedObject var colin: ColinLibrary
    @ObservedObject var router: WindowRouter
    var calendar: Calendar = CalendarView.calendar
    @Environment(\.dismiss) private var dismiss

    /// « Depuis hier 19:40 : 3 projets ont bougé. »
    private var title: String {
        colin.briefing.first { $0.kind == .since }?.sentence ?? "Le point"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            // A sentence with its « : »: French typography (lot 10, 20/11).
            Text(verbatim: Words.typeset(title)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    ForEach(colin.briefingMails) { thread in
                        HStack(spacing: Space.m) {
                            Image(systemName: "envelope").foregroundStyle(.secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                // A subject left empty, said as everywhere (lot 10, 20/11: `Words.noSubject`).
                                Text(thread.subject.isEmpty ? Words.noSubject : thread.subject).font(.rowBody).lineLimit(1)
                                Text(thread.senders.last.map { $0.name ?? $0.email } ?? "").font(.meta).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: Space.s)
                            Button("Ouvrir") {
                                router.homeMail = thread.id
                                dismiss()
                            }
                            // One outline, small, as every button of a line on the Accueil (lot 5, 19/11).
                            .buttonStyle(.secondary)
                            .controlSize(.small)
                        }
                    }
                    ForEach(colin.briefingChanges.reversed()) { line in
                        ChangeCard(line: line, outcome: colin.changeOutcomes[line.id], calendar: calendar,
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
