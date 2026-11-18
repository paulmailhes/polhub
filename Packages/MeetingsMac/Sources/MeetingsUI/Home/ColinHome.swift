import Colin
import PolhubDesign
import SwiftUI

/// Colin's column on the Accueil (18/11): his name and whether he runs, « Le point », and his thread. The bar is
/// placed by the page, under the column.
struct ColinHome: View {
    @ObservedObject var colin: ColinLibrary
    /// `nil`: no bar (captures without the engine, the public build without the mails).
    var thread: ColinThread?
    let mails: MailLibrary?
    @ObservedObject var router: WindowRouter
    /// « Voir »: what moved without Paul, over the Accueil.
    @State private var seeing = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let thread { ColinHeader(thread: thread) }
            if let preparedAt = colin.briefingAt, !colin.briefing.isEmpty {
                BriefingCard(sentences: colin.briefing, preparedAt: preparedAt, see: colin.briefingChanges.isEmpty ? nil : { seeing = true })
                    .transition(.opacity)
            }
            if let thread { ColinThreadView(thread: thread, mails: mails, router: router) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(Motion.standard, value: colin.briefingAt)
        .sheet(isPresented: $seeing) { ChangesSheet(colin: colin) }
    }
}

/// « Colin · en marche » with « Mettre à l'arrêt »; « Colin · à l'arrêt » otherwise (« Allumer Colin » is in the bar's place).
struct ColinHeader: View {
    @ObservedObject var thread: ColinThread

    var body: some View {
        SectionTitle("Colin") {
            HStack(spacing: Space.s) {
                ColorDot(thread.isOn ? Color(hex: Palette.green) : Color.secondary)
                Text(thread.isOn ? "en marche" : "à l'arrêt").font(.callout).foregroundStyle(.secondary)
                if thread.isOn { TextButton("Mettre à l'arrêt") { thread.turnOff() } }
            }
        }
    }
}
