import Foundation
import Persistence

/// What an import did, kind by kind, and its images.
public struct InspirationImportReport: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        /// Items new in Polhub.
        public var added: Int
        /// Items Polhub had, that the vault completed.
        public var updated: Int
        /// Items Polhub had, nothing new.
        public var unchanged: Int
        /// Notes folded into another item: the same key twice, the same project posted by two pages.
        public var duplicates: Int
        /// Notes left aside, each with its warning.
        public var skipped: Int
        /// Items only the second folder (the old copy) had: what the vault missed.
        public var onlyInExtra: Int

        public init(added: Int = 0, updated: Int = 0, unchanged: Int = 0, duplicates: Int = 0, skipped: Int = 0, onlyInExtra: Int = 0) {
            self.added = added
            self.updated = updated
            self.unchanged = unchanged
            self.duplicates = duplicates
            self.skipped = skipped
            self.onlyInExtra = onlyInExtra
        }

        /// The items the vault holds, now in Polhub.
        public var items: Int { added + updated + unchanged }
    }

    public var counts: [InspirationKind: Counts] = [:]
    /// LinkedIn pages added from `_sources.md`.
    public var sourcesAdded = 0
    /// Images made light and written.
    public var imagesConverted = 0
    /// Images already in Polhub, kept as they were.
    public var imagesReused = 0
    /// Branding images beyond the five a post keeps.
    public var imagesLeftOut = 0
    /// What this import wrote.
    public var bytesWritten = 0
    /// What the images of the imported items weigh, written now or before.
    public var imageBytes = 0
    /// One line each: a note's title and what happened, never its content.
    public var warnings: [String] = []
    /// Set when the import stopped before converting everything: what all the images would have weighed.
    public var projectedBytes: Int?

    public init() {}

    public subscript(_ kind: InspirationKind) -> Counts {
        get { counts[kind] ?? Counts() }
        set { counts[kind] = newValue }
    }

    /// « 212 sites, 488 branding, 292 mock-ups ; 640 Mo d'images »; « … ; import arrêté avant la fin : environ
    /// 1 240 Mo d'images en tout » when the weight stopped it.
    public var summary: String {
        let websites = self[.website].items, branding = self[.branding].items, mockups = self[.mockup].items
        let parts = ["\(websites) site\(websites > 1 ? "s" : "")", "\(branding) branding", "\(mockups) mock-up\(mockups > 1 ? "s" : "")"]
        let stopped = projectedBytes.map { " ; import arrêté avant la fin : environ \(Self.weight($0)) en tout" } ?? ""
        return parts.joined(separator: ", ") + " ; " + Self.weight(imageBytes) + stopped
    }

    /// The rest, for whoever wants to know more: « dont 34 seulement dans l'ancienne copie ; 61 doublons
    /// fusionnés ; 3 notes laissées de côté ; 2 pages LinkedIn ajoutées ». Empty when there is nothing to add.
    public var details: String {
        let all = InspirationKind.allCases.map { self[$0] }
        let extra = all.reduce(0) { $0 + $1.onlyInExtra }
        let duplicates = all.reduce(0) { $0 + $1.duplicates }
        let skipped = all.reduce(0) { $0 + $1.skipped }
        var parts: [String] = []
        if extra > 0 { parts.append("dont \(extra) seulement dans l'ancienne copie") }
        if duplicates > 0 { parts.append("\(duplicates) doublon\(duplicates > 1 ? "s" : "") fusionné\(duplicates > 1 ? "s" : "")") }
        if skipped > 0 { parts.append("\(skipped) note\(skipped > 1 ? "s" : "") laissée\(skipped > 1 ? "s" : "") de côté") }
        if sourcesAdded > 0 { parts.append("\(sourcesAdded) page\(sourcesAdded > 1 ? "s" : "") LinkedIn ajoutée\(sourcesAdded > 1 ? "s" : "")") }
        return parts.joined(separator: " ; ")
    }

    /// « 640 Mo d'images », « 1 240 Mo d'images » (a narrow space between thousands), « aucune image ».
    static func weight(_ bytes: Int) -> String {
        guard bytes > 0 else { return "aucune image" }
        let megabytes = max(1, Int((Double(bytes) / 1_000_000).rounded()))
        var digits = String(megabytes)
        var grouped: [String] = []
        while digits.count > 3 {
            grouped.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        grouped.insert(digits, at: 0)
        return grouped.joined(separator: "\u{202F}") + " Mo d'images"
    }
}

public enum InspirationImportError: Error, Equatable, CustomStringConvertible {
    case notAVault(String)

    public var description: String {
        switch self {
        case .notAVault(let path):
            "Ce dossier n'est pas le coffre Obsidian : « database » (Websites, Branding, Mockups) est introuvable dans \(path)."
        }
    }
}
