import CryptoKit
import Foundation

/// The file name of an item's image in its kind's folder (`AppPaths.inspirationImages`), from its key: the
/// import and the collection name them the same way, so an item seen twice reuses its files.
public enum InspirationImageName {
    /// `studio-exemple.fr-projets-1a2b3c4d.jpg`: readable, and unique by the key's hash.
    public static func website(key: String) -> String {
        let readable = key.replacing(#/^[a-zA-Z]+://(www\.)?/#, with: "")
        return "\(slug(readable))-\(shortHash(key)).jpg"
    }

    /// `<urn>-1.jpg`, `<urn>-2.jpg`…, the cover first (`index` from 1).
    public static func branding(urn: String, index: Int) -> String {
        "\(slug(urn))-\(index).jpg"
    }

    /// `affiche-urbaine-1a2b3c4d.jpg`.
    public static func mockup(folder: String) -> String {
        "\(slug(folder))-\(shortHash(folder)).jpg"
    }

    /// Lowercase ASCII letters, digits, dots and dashes; at most `limit` characters.
    static func slug(_ text: String, limit: Int = 60) -> String {
        let ascii = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let cleaned = ascii.replacing(#/[^a-z0-9.]+/#, with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let cut = String(cleaned.prefix(limit)).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return cut.isEmpty ? "image" : cut
    }

    static func shortHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
