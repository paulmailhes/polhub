import Domain
import Foundation
import Persistence

/// The search results, one entry per meeting.
public struct SearchGroup: Equatable, Identifiable, Sendable {
    public struct Excerpt: Equatable, Sendable {
        public let startMs: Int
        public let speaker: Speaker
        public let text: String
    }

    public var id: UUID { meetingID }
    public let meetingID: UUID
    public let title: String
    public let startedAt: Date
    public let excerpts: [Excerpt]
    /// Lines found beyond the ones shown.
    public let more: Int
}

public enum SearchModel {
    public static let excerptsPerMeeting = 5

    public static func shouldSearch(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    /// Newest meetings first; in a meeting, the lines in time order, five at most.
    public static func groups(_ hits: [SearchHit]) -> [SearchGroup] {
        let byMeeting = Dictionary(grouping: hits, by: \.meetingID)
        return byMeeting.values.compactMap { hits -> SearchGroup? in
            guard let first = hits.first else { return nil }
            let sorted = hits.sorted { $0.startMs < $1.startMs }
            return SearchGroup(
                meetingID: first.meetingID, title: first.title, startedAt: first.startedAt,
                excerpts: sorted.prefix(excerptsPerMeeting).map { SearchGroup.Excerpt(startMs: $0.startMs, speaker: $0.speaker, text: $0.excerpt) },
                more: max(0, sorted.count - excerptsPerMeeting)
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }
}
