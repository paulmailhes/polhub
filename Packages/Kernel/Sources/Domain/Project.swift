import Foundation

/// A project's column on the board: four statuses since 15/11 (Paul). The raw values stay lowercase, as the
/// `projets` tool of `hub mcp` writes them.
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    // In Paul's scale the higher number is the more urgent (15/11: « priorité 2 c'est le plus priorité ») :
    // Priorité 2 first, at the left of the board and on top of every list.
    case priorite2 = "priorité 2"
    case priorite1 = "priorité 1"
    case enPause = "en pause"
    case termine = "terminé"

    /// The order of the board's columns: the most urgent at the left, Terminé on the right.
    public static let boardOrder: [ProjectStatus] = allCases

    /// A value read from the base, never refused: an old status (before the migration `v12`, or written by
    /// an older `hub mcp`) finds its new column, anything else goes « En pause ». « priorité 2 » keeps its
    /// meaning here: only the migration moves the old ones.
    public init(tolerant raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let status = ProjectStatus(rawValue: trimmed) {
            self = status
            return
        }
        switch trimmed {
        case "idée": self = .priorite1
        case "priorité 3": self = .priorite2
        default: self = .enPause
        }
    }

    /// An unknown value would otherwise empty the board without a word (review of 15/11).
    public init(from decoder: any Decoder) throws {
        self.init(tolerant: try decoder.singleValueContainer().decode(String.self))
    }

    /// Lowercase, for `hub mcp`: « priorité 1 ».
    public var label: String { rawValue }

    /// For the window: « Priorité 1 ».
    public var title: String {
        switch self {
        case .priorite1: "Priorité 1"
        case .priorite2: "Priorité 2"
        case .enPause: "En pause"
        case .termine: "Terminé"
        }
    }
}
