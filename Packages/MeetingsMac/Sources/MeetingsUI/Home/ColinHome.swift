import Colin
import PolhubDesign
import SwiftUI

/// « Colin · en marche », fixed at the head of the conversation (the Accueil's pass, 18/11): his name, his state, and
/// a « … » with « Mettre à l'arrêt » and his settings. Nothing orange: the bar is where things happen.
struct ColinHeader: View {
    @ObservedObject var thread: ColinThread
    @ObservedObject var router: WindowRouter

    var body: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Text("Colin").font(.system(size: 15, weight: .semibold))
            ColorDot(thread.isOn ? Color(hex: Palette.green) : Color.secondary, size: 7)
            Text(thread.isOn ? "en marche" : "à l'arrêt").font(.meta).foregroundStyle(.secondary)
            Spacer(minLength: Space.s)
            IconMenu("ellipsis", help: "Colin") {
                if thread.isOn { Button("Mettre à l'arrêt") { thread.turnOff() } }
                Button("Réglages…") { router.openSettings(.colin) }
            }
        }
    }
}
