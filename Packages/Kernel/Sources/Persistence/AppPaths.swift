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

    public func meetingFolder(_ id: UUID) -> URL {
        meetings.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }
}
