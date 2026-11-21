import HubDesign
import SwiftUI

/// Coup d'œil's line for Vigie (21/11): how many things wait for Paul in Claude Code, and the way to them. Nothing when
/// nothing waits.
struct PanelVigie: View {
    @ObservedObject var library: VigieLibrary
    let open: () -> Void

    var body: some View {
        let count = library.waiting.count
        if count > 0 {
            Button(action: open) {
                HStack(alignment: .center, spacing: Space.m) {
                    AppIconImage(.vigie, size: 18).foregroundStyle(Color(hex: Palette.cyan))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Words.typeset(count == 1 ? "1 demande t'attend dans Claude Code" : "\(count) demandes t'attendent dans Claude Code"))
                            .font(.callout)
                        Text(Words.typeset(library.waiting.first?.conversationTitle ?? "Vigie")).font(.meta).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: Space.s)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(Space.m)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.control))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir Vigie dans hub")
        }
    }
}
