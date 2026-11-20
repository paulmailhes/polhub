import Foundation

/// The folders hub keeps its data and its logs in, in Application Support and in Library/Logs: `hub-board` since
/// 20/11, `Polhub` before. The app moves the old ones at its first launch under the new name, and leaves a link in their
/// place: a `polhub mcp` still alive in an open session, or the previous version after a rollback, reaches the same base.
public enum AppFolders {
    public static func name(dev: Bool) -> String { dev ? "hub-board-dev" : "hub-board" }
    /// The name before 20/11: a hidden identifier now, kept for the move and the link.
    public static func legacyName(dev: Bool) -> String { dev ? "Polhub-dev" : "Polhub" }

    public static var supportParent: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0] }
    public static var logsParent: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appending(path: "Logs", directoryHint: .isDirectory)
    }

    /// In `parent`: the new folder when it is there, else the old one when it is there (a command started before the
    /// app moved them), else the new one.
    public static func resolve(in parent: URL, dev: Bool, manager: FileManager = .default) -> URL {
        let new = parent.appending(path: name(dev: dev), directoryHint: .isDirectory)
        let old = parent.appending(path: legacyName(dev: dev), directoryHint: .isDirectory)
        if manager.fileExists(atPath: new.path(percentEncoded: false)) { return new }
        if manager.fileExists(atPath: old.path(percentEncoded: false)) { return old }
        return new
    }

    /// The data folder, where it is now.
    public static func support(dev: Bool) -> URL { resolve(in: supportParent, dev: dev) }

    /// Moves the old folder of `parent` under the new name, when it is a real folder and the new one is not there, and
    /// leaves a link in its place. The lines say what was done, for the log; none when nothing was to do.
    public static func moveLegacy(in parent: URL, dev: Bool, manager: FileManager = .default) -> [String] {
        let new = parent.appending(path: name(dev: dev), directoryHint: .isDirectory)
        let old = parent.appending(path: legacyName(dev: dev), directoryHint: .isDirectory)
        var status = stat()
        guard lstat(old.path(percentEncoded: false), &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR,
              !manager.fileExists(atPath: new.path(percentEncoded: false)) else { return [] }
        do {
            try manager.moveItem(at: old, to: new)
        } catch {
            return ["\(old.path(percentEncoded: false)) n'a pas pu devenir \(new.lastPathComponent) : \(error)"]
        }
        do {
            // The link's path without the trailing slash of a folder's URL: with it, nothing is created.
            let link = parent.appending(path: legacyName(dev: dev), directoryHint: .notDirectory).path(percentEncoded: false)
            try manager.createSymbolicLink(atPath: link, withDestinationPath: new.lastPathComponent)
        } catch {
            return ["\(old.lastPathComponent) devient \(new.lastPathComponent), sans lien à l'ancienne place : \(error)"]
        }
        return ["\(old.path(percentEncoded: false)) devient \(new.lastPathComponent), un lien reste à l'ancienne place"]
    }

    /// At the app's launch, before anything opens the base: the data folder and the logs' folder.
    public static func moveLegacyFolders(dev: Bool) -> [String] {
        moveLegacy(in: supportParent, dev: dev) + moveLegacy(in: logsParent, dev: dev)
    }
}
