import PolhubDesign
import SwiftUI

/// « À régler » (15/11): only when something keeps Polhub from working well, one line per cause, three at most, the
/// riskiest for the recordings first. A calm card tinted orange, no glass; each line goes by itself once its cause is
/// gone. It shows what is known and never runs a test.
struct PanelAttention: View {
    let issues: [PanelModel.Issue]
    let perform: (PanelModel.Issue.Action) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.self) private var environment

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(issues) { issue in
                RowButton(action: { perform(issue.action) }) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PanelTint.orange.readable(in: environment))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(issue.title)
                                .font(.rowBody.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = issue.detail {
                                // Two lines, whatever the number of causes: cut to one, « par le micro seul » lost
                                // its « seul », the very word that says what is wrong (finding of 16/11). Three causes
                                // at most keep the banner short.
                                Text(detail)
                                    .font(.meta)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: Space.xs)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .help(issue.help)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelTint.orange.opacity(scheme == .dark ? 0.16 : 0.12), in: shape)
        .overlay(shape.strokeBorder(PanelTint.edge(PanelTint.orange, dark: scheme == .dark)))
    }
}
