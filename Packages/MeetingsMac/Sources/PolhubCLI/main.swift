import Foundation
import Persistence
import ReadingKit

/// `polhub`: Paul's meetings for the terminal, read-only, and for Claude Code the meetings and the projects
/// (`polhub mcp`, whose project tools write).
let usage = """
Usage :
  polhub reunions [--depuis AAAA-MM-JJ] [--limite N]
  polhub reunion <numéro | début d'id | morceau du titre> [--page N]
  polhub chercher <texte> [--limite N]
  polhub mcp            (serveur MCP sur l'entrée et la sortie standard)
Option : --base <chemin de Polhub.sqlite>
"""

var arguments = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let basePath = option("--base") ?? AppPaths.standard(.prod).database.path(percentEncoded: false)
guard let command = arguments.first, command != "--help", command != "-h" else {
    print(usage)
    exit(0)
}
guard FileManager.default.fileExists(atPath: basePath) else { fail("La base des réunions est introuvable : \(basePath)") }
let database: AppDatabase
do { database = try AppDatabase.forReading(path: basePath) } catch { fail("La base ne s'ouvre pas : \(error)") }
guard (try? database.isAtStep2()) == true else {
    fail("La base des réunions n'est pas encore à jour : la dernière version de Polhub doit être ouverte une fois.")
}
let reader = MeetingReader(meetings: MeetingStore(database), transcripts: TranscriptStore(database))

do {
    switch command {
    case "reunions":
        let since = option("--depuis")
        var date: Date?
        if let since {
            guard let day = MCPServer.day(since) else { fail("--depuis attend une date AAAA-MM-JJ.") }
            date = day
        }
        print(try reader.list(since: date, limit: Int(option("--limite") ?? "") ?? 20))
    case "reunion":
        let page = Int(option("--page") ?? "") ?? 1
        guard arguments.count >= 2 else { fail(usage) }
        print(try reader.meeting(arguments.dropFirst().joined(separator: " "), page: page))
    case "chercher":
        let limit = Int(option("--limite") ?? "") ?? 20
        guard arguments.count >= 2 else { fail(usage) }
        print(try reader.search(arguments.dropFirst().joined(separator: " "), limit: limit))
    case "mcp":
        let helper = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        // The project tools write (13/11): the base opens for writing, never migrated, and the app is told.
        var desk: ProjectDesk?
        if let tools = try? AppDatabase.forTools(path: basePath), (try? tools.hasProjects()) == true {
            desk = ProjectDesk(projects: ProjectStore(tools), meetings: MeetingStore(tools),
                               workingDirectory: FileManager.default.currentDirectoryPath)
        }
        // The mails (step « Agents »): the copy, read; drafts dropped for the app. No network here.
        var mails: MailDesk?
        if let tools = try? AppDatabase.forTools(path: basePath), (try? MailStore(tools).acceptsAgentDrafts()) == true {
            mails = MailDesk(database: tools, root: URL(fileURLWithPath: basePath).deletingLastPathComponent(), scope: .current(), projects: desk)
        }
        let server = MCPServer(reader: reader, desk: desk, mails: mails, version: HelperVersion.read(helper: helper) ?? "0.0.0",
                               onWrite: { ExternalChangeSignal.post() })
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, let answer = server.handle(line) else { continue }
            FileHandle.standardOutput.write(Data((answer + "\n").utf8))
        }
    default:
        fail(usage)
    }
} catch {
    fail("\(error)")
}
