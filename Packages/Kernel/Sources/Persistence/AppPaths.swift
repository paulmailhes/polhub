import Domain
import Foundation

/// Where the app keeps its data. The development flavor has its own folders: it never reads or writes the
/// production base or recordings.
public struct AppPaths: Sendable, Equatable {
    public let root: URL
    public let logs: URL

    public init(root: URL, logs: URL) {
        self.root = root
        self.logs = logs
    }

    public static func standard(_ flavor: AppFlavor) -> AppPaths {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let library = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let name = flavor == .dev ? "Polhub-dev" : "Polhub"
        return AppPaths(
            root: support.appending(path: name, directoryHint: .isDirectory),
            logs: library.appending(path: "Logs/\(name)", directoryHint: .isDirectory)
        )
    }

    public var database: URL { root.appending(path: "Polhub.sqlite") }
    public var meetings: URL { root.appending(path: "Reunions", directoryHint: .isDirectory) }
    public var backups: URL { root.appending(path: "Sauvegardes", directoryHint: .isDirectory) }
    /// The projects' logos, and the sites they come from (15/11): outside the base.
    public var logos: URL { root.appending(path: "Logos", directoryHint: .isDirectory) }
    /// The notifications Polhub sent, as its own list shows them (15/11): a small file, outside the base.
    public var notifications: URL { root.appending(path: "Notifications.json") }

    public func meetingFolder(_ id: UUID) -> URL {
        meetings.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }
}
