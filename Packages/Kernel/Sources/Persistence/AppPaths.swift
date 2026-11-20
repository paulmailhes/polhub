import Domain
import Foundation
import Observability

/// Where the app keeps its data. The development flavor has its own folders: it never reads or writes the
/// production base or recordings.
public struct AppPaths: Sendable, Equatable {
    public let root: URL
    public let logs: URL

    public init(root: URL, logs: URL) {
        self.root = root
        self.logs = logs
    }

    /// The folders `hub-board` (20/11), or `Polhub` while the app has not moved them yet (`AppFolders`).
    public static func standard(_ flavor: AppFlavor) -> AppPaths {
        AppPaths(
            root: AppFolders.resolve(in: AppFolders.supportParent, dev: flavor == .dev),
            logs: AppFolders.resolve(in: AppFolders.logsParent, dev: flavor == .dev)
        )
    }

    /// A hidden identifier: the base keeps its file name of before 20/11, so that the previous version, after a
    /// rollback, and a `polhub mcp` of an open session open the same base.
    public static let databaseFileName = "Polhub.sqlite"

    public var database: URL { root.appending(path: Self.databaseFileName) }
    public var meetings: URL { root.appending(path: "Reunions", directoryHint: .isDirectory) }
    public var backups: URL { root.appending(path: "Sauvegardes", directoryHint: .isDirectory) }
    /// The projects' logos, and the sites they come from (15/11): outside the base.
    public var logos: URL { root.appending(path: "Logos", directoryHint: .isDirectory) }
    /// The notifications Polhub sent, as its own list shows them (15/11): a small file, outside the base.
    public var notifications: URL { root.appending(path: "Notifications.json") }
    /// « Inspiration » (16/11): the images of the sites, the branding and the mock-ups, outside the base (the
    /// base's copies stay small), and the vocabularies brought from the vault.
    public var inspiration: URL { root.appending(path: "Inspiration", directoryHint: .isDirectory) }

    public func inspirationImages(_ kind: InspirationKind) -> URL {
        inspiration.appending(path: kind.folderName, directoryHint: .isDirectory)
    }

    public func meetingFolder(_ id: UUID) -> URL {
        meetings.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }
}
