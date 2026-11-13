public enum ProbeID: String, CaseIterable, Sendable, Codable {
    case permissions
    case tabs
    case micHolders = "mic-holders"
    case capture
    case devices
    case hud
    case crashWriter = "crash-writer"
    case call
    case record
    case pipeline

    /// Title shown in the probes window.
    public var title: String {
        switch self {
        case .permissions: "Autorisations et relance"
        case .tabs: "Onglets de Dia"
        case .micHolders: "Qui tient le micro"
        case .capture: "Capture du son de Dia"
        case .devices: "Changements de périphérique"
        case .hud: "Pop-up"
        case .crashWriter: "Arrêt brutal"
        case .call: "Appel d'essai"
        case .record: "Enregistreur de réunion"
        case .pipeline: "Chaîne complète (enregistrer, finaliser, relire)"
        }
    }
}

public struct ProbeRequest: Equatable, Sendable {
    public let probe: ProbeID
    public let seconds: Int
    public let variant: String?
    public let quitWhenDone: Bool

    public init(probe: ProbeID, seconds: Int = 60, variant: String? = nil, quitWhenDone: Bool = false) {
        self.probe = probe
        self.seconds = seconds
        self.variant = variant
        self.quitWhenDone = quitWhenDone
    }
}
