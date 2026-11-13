import Foundation

/// Who speaks: the two tracks of a meeting. No names (validated choice).
public enum Speaker: String, Codable, Sendable, CaseIterable {
    case moi, autres
    /// An imported transcript, voices not told apart.
    case unknown

    public var label: String {
        switch self {
        case .moi: "Moi"
        case .autres: "Les autres"
        case .unknown: "Transcription"
        }
    }
}

/// The work done after a meeting. Step 3 adds the summary.
public enum JobKind: String, Codable, Sendable {
    case transcription
}

public enum JobState: String, Codable, Sendable {
    case queued, running, done, failed
}
