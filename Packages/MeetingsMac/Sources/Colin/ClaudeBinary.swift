import Foundation

/// Where Claude Code lives on this Mac. An app starts with a short PATH: looking for « claude » there is not enough.
/// In order: the official install, the usual managers, the PATH, then the copy that comes with an editor's extension
/// or with the Claude app (whoever uses Claude Code in an editor has it, even without the command line).
public enum ClaudeBinary {
    private static let editors = [".vscode", ".vscode-insiders", ".cursor", ".windsurf"]

    /// Where Claude Code may live, the likeliest first. `list` gives the names inside a folder.
    public static func candidates(home: URL, path: String?, list: (URL) -> [String]) -> [URL] {
        var all = official(home) + managers(home)
        let nvm = home.appending(path: ".nvm/versions/node")
        for version in list(nvm).sorted(by: newer) {
            all.append(nvm.appending(path: version).appending(path: "bin/claude"))
        }
        for directory in (path ?? "").split(separator: ":") {
            all.append(URL(fileURLWithPath: String(directory)).appending(path: "claude"))
        }
        for editor in editors {
            let extensions = home.appending(path: editor).appending(path: "extensions")
            for name in list(extensions).filter({ $0.hasPrefix("anthropic.claude-code-") }).sorted(by: newer) {
                all.append(extensions.appending(path: name).appending(path: "resources/native-binary/claude"))
            }
        }
        let app = home.appending(path: "Library/Application Support/Claude/claude-code")
        for version in list(app).sorted(by: newer) {
            for build in list(app.appending(path: version)).sorted() {
                all.append(app.appending(path: version).appending(path: build).appending(path: "claude.app/Contents/MacOS/claude"))
            }
        }
        return all
    }

    public static func find(home: URL, path: String?, list: (URL) -> [String], isExecutable: (URL) -> Bool) -> URL? {
        candidates(home: home, path: path, list: list).first(where: isExecutable)
    }

    /// The live search: the user's home, the process's PATH, the real disk.
    public static func find() -> URL? {
        let manager = FileManager.default
        return find(
            home: manager.homeDirectoryForCurrentUser, path: ProcessInfo.processInfo.environment["PATH"],
            list: { (try? manager.contentsOfDirectory(atPath: $0.path(percentEncoded: false))) ?? [] },
            isExecutable: { url in
                let path = url.path(percentEncoded: false)
                var isDirectory: ObjCBool = false
                return manager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue && manager.isExecutableFile(atPath: path)
            })
    }

    /// « officiel », « gestionnaire », « chemin », « éditeur », « app »: what a trace may say, never the path itself.
    public static func kind(of binary: URL, home: URL) -> String {
        let path = binary.path(percentEncoded: false)
        if official(home).contains(where: { $0.path(percentEncoded: false) == path }) { return "officiel" }
        if path.contains("/extensions/anthropic.claude-code-") { return "éditeur" }
        if path.contains("/Claude/claude-code/") { return "app" }
        if managers(home).contains(where: { $0.path(percentEncoded: false) == path }) || path.contains("/.nvm/versions/node/") { return "gestionnaire" }
        return "chemin"
    }

    private static func official(_ home: URL) -> [URL] {
        [home.appending(path: ".local/bin/claude"), home.appending(path: ".claude/local/claude")]
    }

    private static func managers(_ home: URL) -> [URL] {
        [URL(fileURLWithPath: "/opt/homebrew/bin/claude"), URL(fileURLWithPath: "/usr/local/bin/claude"),
         home.appending(path: ".npm-global/bin/claude"), home.appending(path: ".volta/bin/claude"), home.appending(path: ".bun/bin/claude")]
    }

    /// « 2.1.304-darwin-arm64 » → [2, 1, 304].
    static func version(_ name: String) -> [Int] {
        guard let match = name.firstMatch(of: /(\d+)\.(\d+)\.(\d+)/) else { return [0, 0, 0] }
        return [Int(match.1) ?? 0, Int(match.2) ?? 0, Int(match.3) ?? 0]
    }

    /// The newest first; two names of the same version keep the order of their letters.
    private static func newer(_ a: String, _ b: String) -> Bool {
        let x = version(a), y = version(b)
        return x == y ? a < b : y.lexicographicallyPrecedes(x)
    }
}
