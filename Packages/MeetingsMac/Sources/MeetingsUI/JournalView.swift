import Domain
import Persistence
import SwiftUI

/// Missed meetings, alerts and notes, the latest first.
struct JournalView: View {
    let entries: [JournalEntry]

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView("Journal vide", systemImage: "checkmark.circle",
                                   description: Text("Aucune réunion manquée, aucune alerte."))
        } else {
            List(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    icon(entry.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message).fixedSize(horizontal: false, vertical: true)
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder private func icon(_ kind: JournalKind) -> some View {
        switch kind {
        case .missed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .alert: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
    }
}
