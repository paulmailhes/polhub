import Persistence
import PolhubDesign
import SwiftUI

/// « Nouveaux mails » (15/11): the unread mails of people in the inbox, those filed in a project first (a dot of its
/// color), then those of a known contact, then the others; three at most, then « Voir les N autres » opens Mails.
/// Hidden during a meeting. The only part of the panel that gives way under its height cap: by whole rows, never a row
/// cut through its subject, the link counting every mail it does not show; with no room for a row, its header and
/// « Voir les N nouveaux » alone (finding of 16/11).
struct PanelMailCard: View {
    let lines: [PanelModel.MailLine]
    @ObservedObject var mails: MailLibrary
    /// The rows the panel's cap leaves room for (`PanelModel.mailRowsShown`).
    let rows: Int
    let open: (WindowRouter.Place) -> Void
    /// One row's height, and the card's without its rows: measured while rows show.
    let measured: (_ rowHeight: CGFloat, _ chrome: CGFloat) -> Void
    @State private var rowHeight: CGFloat = 0
    @State private var card: CGFloat = 0

    var body: some View {
        let shown = Array(lines.prefix(min(max(0, rows), PanelModel.mailLimit)))
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nouveaux mails").font(.meta.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(lines.count)").font(.meta.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { line in
                        PanelMailRow(line: line, open: { open(.mail(line.id)) }, markRead: { mails.markRead(line.thread) })
                            // The rows are alike: the first one's height is the others'.
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                guard line.id == shown.first?.id else { return }
                                rowHeight = height
                                report(rows: shown.count)
                            }
                    }
                }
            }
            if let more = PanelModel.moreMails(total: lines.count, shown: shown.count) {
                Button { open(.mail(nil)) } label: {
                    HStack(spacing: Space.xs) {
                        Text(more)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.meta.weight(.medium))
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xs)
                }
                .buttonStyle(.hover(.capsule))
                .foregroundStyle(.secondary)
                .padding(.horizontal, -Space.s)
                // Its capsule spills into the card's padding: the line costs only its text, a third mail fits at rest.
                .padding(.vertical, -2)
                .help("Ouvrir la boîte de réception (⌘5)")
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelSurface.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(PanelSurface.edge))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            card = height
            report(rows: shown.count)
        }
    }

    /// The card and its rows come from the same layout, so the card less its rows is its chrome; with no row shown,
    /// nothing is told (the chrome measured with rows stays).
    private func report(rows: Int) {
        guard rows > 0, rowHeight > 0, card > 0 else { return }
        measured(rowHeight, card - rowHeight * CGFloat(rows))
    }
}

/// A mail: the sender, its time, the subject. Under the pointer, « Marquer comme lu » takes the time's place, over it,
/// on the sender's line: nothing moves, the subject stays whole, and the panel stays open.
struct PanelMailRow: View {
    let line: PanelModel.MailLine
    let open: () -> Void
    let markRead: () -> Void
    @State private var hovering: Bool

    /// `hovering` is for the captures, which cannot point at a row.
    init(line: PanelModel.MailLine, open: @escaping () -> Void, markRead: @escaping () -> Void, hovering: Bool = false) {
        self.line = line
        self.open = open
        self.markRead = markRead
        _hovering = State(initialValue: hovering)
    }

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
        // Lined up on the sender's line, where the time was: its glyph sits on that line's middle, 5 points above the
        // baseline, and never over the subject.
        .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
            if hovering {
                IconButton("envelope.open", help: "Marquer comme lu", action: markRead)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    .padding(.trailing, -6)
                    .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help("Ouvrir le fil dans Mails")
    }
}
