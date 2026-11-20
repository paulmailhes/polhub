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
    /// Step 0 of Colin (17/11): Claude Code launched by hub, on invented texts.
    case colin
    /// The rules of « À valider », counted on the mails of the base (18/11): numbers only, no model, nothing sent.
    case colinRules = "colin-regles"

    /// The probes offered in the window of the probes. Colin's is not: it has its own button on the Diagnostic page,
    /// with the account it uses and its guards (never during a meeting).
    public static var listed: [ProbeID] { allCases.filter { $0 != .colin } }

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
        case .colin: "Colin : Claude Code depuis hub"
        case .colinRules: "Colin : les règles sur tes mails"
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
