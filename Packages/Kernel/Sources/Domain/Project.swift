import Foundation

/// A project's column on the board: the statuses of Paul's Obsidian vault, with the same raw values.
public enum ProjectStatus: String, Codable, Sendable, CaseIterable {
    case idee = "idée"
    case priorite3 = "priorité 3"
    case priorite2 = "priorité 2"
    case priorite1 = "priorité 1"
    case enAttente = "en attente"
    case termine = "terminé"
    /// A status missing or unknown in the vault (« Uncategorized » in Obsidian).
    case none = ""

    /// The order of the board's columns, as in `Projets.base`.
    public static let boardOrder: [ProjectStatus] = [.idee, .priorite3, .priorite2, .priorite1, .enAttente, .termine, .none]

    public init(obsidian: String?) {
        self = obsidian.flatMap { ProjectStatus(rawValue: $0.trimmingCharacters(in: .whitespaces)) } ?? .none
    }

    public var label: String { self == .none ? "Sans statut" : rawValue }

    /// Priority 1, 2 or 3: the projects « À rendre » and « À surveiller » look at.
    public var isPriority: Bool { [.priorite1, .priorite2, .priorite3].contains(self) }
}
