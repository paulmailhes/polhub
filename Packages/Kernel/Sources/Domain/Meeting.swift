import Foundation

/// Where a meeting is in its life. `pending`: the pop-up is shown and the pre-recording runs.
public enum MeetingStatus: String, Codable, Sendable, CaseIterable {
    case pending, recording, presumedEnded, ended, interrupted, discarded

    /// A meeting the app may still be recording, or must close after a crash.
    public var isUnfinished: Bool { [.pending, .recording, .presumedEnded].contains(self) }
}

/// `dia`: a Meet in Dia, Dia's sound and the microphones Dia holds. `wholeMac`: « Enregistrer maintenant »,
/// the whole Mac's sound and the default microphone.
public enum MeetingSource: String, Codable, Sendable {
    case dia, wholeMac
}

public enum EndReason: String, Codable, Sendable {
    case tabClosed, safetyElapsed, diaQuit, userStopped, interrupted
    /// Dia took the microphone again for a meeting in another tab.
    case nextMeeting
}

public enum JournalKind: String, Codable, Sendable {
    case missed, alert, info
}

/// The production app and the development one never share their data.
public enum AppFlavor: String, Sendable {
    case prod, dev

    /// Read from the `TRNFlavor` key of the app's Info.plist; absent means production.
    public static var current: AppFlavor {
        (Bundle.main.object(forInfoDictionaryKey: "TRNFlavor") as? String).flatMap(AppFlavor.init(rawValue:)) ?? .prod
    }
}
