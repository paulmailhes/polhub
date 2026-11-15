import Persistence
import PolhubDesign
import SwiftUI

/// « Nouveaux mails » (15/11): the unread mails of people in the inbox, those filed in a project first (a dot of its
/// color), then those of a known contact, then the others; three at most, then « Voir les N autres » opens Mails.
/// Hidden during a meeting. The only part of the panel that scrolls, past its height cap.
struct PanelMailCard: View {
    let lines: [PanelModel.MailLine]
    @ObservedObject var mails: MailLibrary
    /// The height the panel gives the list; nil before it measured the rows.
    let listFrame: CGFloat?
    let open: (WindowRouter.Place) -> Void
    /// The rows' own height, and the card's without its list.
    let measured: (_ rows: CGFloat, _ chrome: CGFloat) -> Void
    @State private var rows: CGFloat = 0
    @State private var card: CGFloat = 0
    @State private var list: CGFloat = 0

    var body: some View {
        let shown = Array(lines.prefix(PanelModel.mailLimit))
        let hidden = lines.count - shown.count
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nouveaux mails").font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(lines.count)").font(.meta.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { line in
                        PanelMailRow(line: line, open: { open(.mail(line.id)) }, markRead: { mails.markRead(line.thread) })
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rows = $0; report() }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.automatic)
            // Its rows' height until the panel measured them, then what the cap leaves it.
            .frame(height: listFrame)
            .fixedSize(horizontal: false, vertical: listFrame == nil)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { list = $0; report() }
            if hidden > 0 {
                Button { open(.mail(nil)) } label: {
                    HStack(spacing: Space.xs) {
                        Text(hidden == 1 ? "Voir l'autre" : "Voir les \(hidden) autres")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.meta.weight(.medium))
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                }
                .buttonStyle(.hover(.capsule))
                .foregroundStyle(.secondary)
                .padding(.horizontal, -Space.s)
                .help("Ouvrir la boîte de réception (⌘5)")
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelSurface.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(PanelSurface.edge))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { card = $0; report() }
    }

    private func report() {
        guard rows > 0, card > 0, list > 0 else { return }
        measured(rows, card - list)
    }
}

/// A mail: the sender, its time, the subject. Under the pointer, « Marquer comme lu » takes the time's place, over it:
/// nothing moves, and the panel stays open.
private struct PanelMailRow: View {
    let line: PanelModel.MailLine
    let open: () -> Void
    let markRead: () -> Void
    @State private var hovering = false

    var body: some View {
        RowButton(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                ColorDot(line.projectTint.map { Color(hex: $0) } ?? .clear, size: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(line.sender)
                            .font(.rowTitle.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: Space.s)
                        Text(line.time)
                            .font(.meta.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .opacity(hovering ? 0 : 1)
                    }
                    Text(line.subject)
                        .font(.rowBody)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if hovering {
                IconButton("envelope.open", help: "Marquer comme lu", action: markRead)
                    .padding(.trailing, -6)
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help("Ouvrir le fil dans Mails")
    }
}
