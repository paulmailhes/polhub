import Domain
import Persistence
import HubDesign
import SwiftUI

/// What the search found, by meeting; a line opens its meeting at that moment.
struct SearchResultsView: View {
    let query: String
    let transcripts: TranscriptStore
    let open: (UUID, Double) -> Void

    @State private var groups: [SearchGroup] = []
    @State private var searched = false

    var body: some View {
        Group {
            if groups.isEmpty {
                // « Aucun résultat pour « x » », as Contacts says it; the typography around what Paul typed, never inside
                // it (lot 10, 20/11: « Rien trouvé »).
                ContentUnavailableView(searched ? Words.typeset("Aucun résultat pour « ") + query + Words.typeset(" »") : "Recherche…",
                                       systemImage: "magnifyingglass",
                                       description: Text(searched ? "La recherche porte sur les transcriptions des réunions." : ""))
            } else {
                List {
                    ForEach(groups) { group in
                        // « 18 nov., 14:00 », by `Words` (lot 10, 20/11).
                        Section("\(group.title) · \(Words.shortDate(group.startedAt, now: Date())), \(Words.time(group.startedAt))") {
                            ForEach(Array(group.excerpts.enumerated()), id: \.offset) { _, excerpt in
                                Button {
                                    open(group.meetingID, Double(excerpt.startMs) / 1_000)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(TranscriptModel.timestamp(excerpt.startMs)) · \(excerpt.speaker.label)")
                                            .font(.meta.monospacedDigit()).foregroundStyle(.secondary)
                                        Text(excerpt.text).font(.rowBody).foregroundStyle(.primary).lineLimit(3)
                                    }
                                    .padding(.vertical, Space.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.row(inset: Space.s))
                            }
                            if group.more > 0 {
                                Text("et " + Words.count(group.more, "autre passage", "autres passages"))
                                    .font(.meta).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: query) {
            // A pause in the typing before searching.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            groups = SearchModel.groups((try? transcripts.search(query, limit: 300)) ?? [])
            searched = true
        }
    }
}
