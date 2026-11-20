import HubDesign
import SwiftUI

/// « À régler » (15/11): only when something keeps Polhub from working well, one line per cause, three at most, the
/// riskiest for the recordings first. Drawn as the app's bands (`Banner`, lot 9, 20/11): the panel's calm card, its
/// fill and its stroke, where only the icon carries attention's color (`Tint.attention`); the title and the detail stay in
/// the text's colors. A card of the panel, it has the others' radius (16), and its causes share it: three bands would
/// stand 50 points taller. No glass. Each line goes by itself once its cause is gone. It shows what is known and never
/// runs a test.
struct PanelAttention: View {
    let issues: [PanelModel.Issue]
    let perform: (PanelModel.Issue.Action) -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(issues) { issue in
                RowButton(action: { perform(issue.action) }) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        // The band's icon of attention, at its size.
                        Image(systemName: "exclamationmark.triangle")
                            .font(.rowTitle.weight(.medium))
                            .foregroundStyle(Tint.attention)
                        VStack(alignment: .leading, spacing: 2) {
                            // French typography, as a band's (`Words.typeset`, lot 10, 20/11).
                            Text(Words.typeset(issue.title))
                                .font(.meta.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = issue.detail {
                                // Two lines, whatever the number of causes: cut to one, « par le micro seul » lost
                                // its « seul », the very word that says what is wrong (finding of 16/11). Three causes
                                // at most keep the card short.
                                Text(Words.typeset(detail))
                                    .font(.meta)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Space.xs)
                        Image(systemName: "chevron.right")
                            .font(.tag.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .help(issue.help)
            }
        }
        // As the mails' card: 12 on the sides, 8 above and under, which the rows' own 4 bring to 12 (lot 9, 20/11).
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelSurface.card, in: shape)
        .overlay(shape.strokeBorder(PanelSurface.edge))
    }
}
