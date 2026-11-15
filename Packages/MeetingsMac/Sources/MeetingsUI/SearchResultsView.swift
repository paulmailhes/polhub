import Domain
import Persistence
import PolhubDesign
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
                ContentUnavailableView(searched ? "Rien trouvé" : "Recherche…", systemImage: "magnifyingglass",
                                       description: Text(searched ? "Aucune transcription ne contient « \(query) »." : ""))
            } else {
                List {
                    ForEach(groups) { group in
                        Section("\(group.title) · \(group.startedAt.formatted(date: .abbreviated, time: .shortened))") {
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
                                Text("et \(group.more) autre\(group.more > 1 ? "s" : "") passage\(group.more > 1 ? "s" : "")")
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
