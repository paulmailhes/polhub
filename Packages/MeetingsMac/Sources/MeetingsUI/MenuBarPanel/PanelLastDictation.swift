import HubDesign
import SwiftUI

/// Coup d'œil's last dictation (20/11, Paul: « recopier facilement le dernier historique »): its words on two lines, its
/// time, and « Copier », which says it copied.
struct PanelLastDictation: View {
    @ObservedObject var library: DictationLibrary
    @State private var copied = false

    var body: some View {
        if let last = library.history.first {
            HStack(alignment: .center, spacing: Space.m) {
                AppIconImage(.dictation, size: 18).foregroundStyle(Color(hex: Palette.indigo))
                VStack(alignment: .leading, spacing: 2) {
                    Text(last.text).lineLimit(2).font(.callout)
                    Text("Dernière dictée · " + Words.shortMoment(last.createdAt, now: Date())).font(.meta).foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.s)
                Button(copied ? "Copiée" : "Copier") {
                    library.copy(last)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(Space.m)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.control))
        }
    }
}
