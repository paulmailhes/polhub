import AppKit
import Domain
import Foundation
import Persistence
import Summarization
import UniformTypeIdentifiers

/// « Exporter » a meeting (Paul, 16/11: « exporter en .md facilement… pour les envoyer à des gens »): one Markdown
/// page with who and when, the summary and its actions, then the dialogue by turns of speech. « Moi » is Paul's
/// first name there: the page is read by others.
enum MeetingExport {
    static func markdown(title: String, date: String, duration: String, participants: [String], summary: String?,
                         actions: [ActionRow], lines: [UtteranceRow], me: String) -> String {
        var parts = ["# \(title)"]
        var meta = duration.isEmpty ? date : "\(date) · \(duration)"
        if !participants.isEmpty { meta += "\nParticipants : " + participants.joined(separator: ", ") }
        parts.append(meta)
        if let summary {
            let clean = SummaryText.exportMarkdown(summary)
            if !clean.isEmpty { parts.append(clean) }
        }
        if !actions.isEmpty {
            parts.append("## Actions\n\n" + actions.map { action in
                "- [\(action.done ? "x" : " ")] \(action.text)" + (action.owner.map { " — \($0)" } ?? "")
            }.joined(separator: "\n"))
        }
        let paragraphs = TranscriptModel.paragraphs(lines)
        if !paragraphs.isEmpty {
            parts.append("## Transcription")
            for paragraph in paragraphs {
                guard paragraph.speaker != .unknown else {
                    parts.append(paragraph.text)
                    continue
                }
                let who = paragraph.speaker == .moi ? me : paragraph.speaker.label
                parts.append("**\(who)** · \(TranscriptModel.timestamp(paragraph.startMs))\n\(paragraph.text)")
            }
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// « 2026-11-16 Refonte du site.md », without a character a folder refuses.
    static func fileName(title: String, date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        var name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Réunion" }
        return "\(day) \(String(name.prefix(120))).md"
    }

    /// The first name of the Mac's account (« Paul Exemple » → « Paul »), else « Moi ».
    static func firstName(_ fullName: String = NSFullUserName()) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? Speaker.moi.label
    }

    /// Asks where, then writes the page; `nil` when Paul cancelled, else the file written or why it failed.
    @MainActor
    static func save(_ page: String, suggestedName: String) -> Result<URL, Error>? {
        let panel = NSSavePanel()
        panel.title = "Exporter la réunion"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try page.write(to: url, atomically: true, encoding: .utf8)
            return .success(url)
        } catch {
            return .failure(error)
        }
    }
}
