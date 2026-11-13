import Foundation
import Persistence
import ReadingKit

/// `transcriptor`: Paul's meetings, read-only, for the terminal and for Claude Code (`transcriptor mcp`).
let usage = """
Usage :
  transcriptor reunions [--depuis AAAA-MM-JJ] [--limite N]
  transcriptor reunion <numéro | début d'id | morceau du titre> [--page N]
  transcriptor chercher <texte> [--limite N]
  transcriptor mcp            (serveur MCP sur l'entrée et la sortie standard)
Option : --base <chemin de Transcriptor.sqlite>
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
do { database = try AppDatabase.readOnly(path: basePath) } catch { fail("La base ne s'ouvre pas : \(error)") }
guard (try? database.isAtStep2()) == true else {
    fail("La base des réunions n'est pas encore à jour : la dernière version de Transcriptor doit être ouverte une fois.")
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
        let server = MCPServer(reader: reader)
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
