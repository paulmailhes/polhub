import Domain
import Persistence
import PolhubDesign
import SwiftUI

/// Missed meetings, alerts and notes, the latest first.
struct JournalView: View {
    let entries: [JournalEntry]

    var body: some View {
        if entries.isEmpty {
            // An empty state: « Aucun … », then how the page fills (lot 10, 20/11).
            ContentUnavailableView("Aucune alerte", systemImage: "checkmark.circle",
                                   description: Text("Polhub note ici les réunions manquées et ce qui n'a pas marché."))
        } else {
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    icon(entry.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message).font(.rowBody).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        // A meta: « 9:04 » today, « hier 9:04 », « 18 nov. 9:04 », by `Words` (lot 10, 20/11).
                        Text(Words.shortMoment(entry.createdAt, now: Date()))
                            .font(.meta.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Space.xs)
            }
        }
    }

    /// A missed meeting and an alert in the one color of « something is wrong », the symbol tells which (design system
    /// v2, 19/11).
    @ViewBuilder private func icon(_ kind: JournalKind) -> some View {
        switch kind {
        case .missed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Tint.attention)
        case .alert: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Tint.attention)
        case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
    }
}
