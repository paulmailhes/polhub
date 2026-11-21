import HubDesign
import SwiftUI
import VigieKit

/// Coup d'œil's line for Vigie (21/11): how many decisions wait for Paul in Claude Code and the way to them, and
/// Auto-accept, as the app Vigie's menu (Paul's choice of 21/11: hub's own icon, no second one).
struct PanelVigie: View {
    @ObservedObject var library: VigieLibrary
    let open: () -> Void

    var body: some View {
        let count = library.decisions.count
        VStack(alignment: .leading, spacing: Space.s) {
            if count > 0 {
                Button(action: open) {
                    HStack(alignment: .center, spacing: Space.m) {
                        ToolBadge(.vigie, color: Palette.cyan, size: .sidebar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Words.typeset(count == 1 ? "1 décision t'attend dans Claude Code" : "\(count) décisions t'attendent dans Claude Code"))
                                .font(.callout)
                            Text(Words.typeset(library.decisions.first.map { [$0.conversationTitle, $0.title].compactMap { $0 }.joined(separator: " · ") } ?? "Vigie"))
                                .font(.meta).foregroundStyle(.secondary).lineLimit(1)
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
            if let settings = library.settings {
                Toggle(isOn: Binding(get: { settings.autoAccept }, set: { on in Task { await library.setAutoAccept(on) } })) {
                    Label("Auto-accept de Claude Code", systemImage: settings.autoAccept ? "binoculars.fill" : "binoculars")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(VigieWords.autoAcceptHelp)
            }
        }
    }
}
