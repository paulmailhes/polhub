import Domain
import Foundation

/// What the Mac has, as the add-ons need it (21/11): read by the app each time a tile asks.
public struct AddOnFacts: Equatable, Sendable {
    public enum Permission: Equatable, Sendable {
        case granted, notAsked, denied
    }

    /// The transcription model is on the disk.
    public var modelsReady = true
    public var microphone = Permission.granted
    public var accessibility = true
    /// Réunions' list (the others' sound, Dia) went green once in the Diagnostic.
    public var meetingsChecked = true
    /// hub's Google key is on this Mac.
    public var googleKey = true
    public var googleAccounts = 0
    /// The accounts whose mails Google lets hub read.
    public var mailboxes = 0
    public var claudeFound = true
    public var colinOn = true
    public var iCloud = true
    public var phones = 0
    /// Vigie's engine has run on this Mac, and it answers now.
    public var vigieInstalled = true
    public var vigieRunning = true

    public init() {}
}

/// What a need's button does.
public enum AddOnAction: String, Equatable, Sendable {
    case askMicrophone, askAccessibility, openDiagnostic, connectGoogle, openGoogleAccounts, openColin, openPhone

    /// It leads to another page: the guide closes first.
    public var leavesThePage: Bool {
        switch self {
        case .askMicrophone, .askAccessibility, .connectGoogle: false
        case .openDiagnostic, .openGoogleAccounts, .openColin, .openPhone: true
        }
    }
}

/// One thing an add-on needs to work (21/11, Paul: « ça dit qu'il faut un compte… qu'on puisse mettre tout ce qu'il
/// faut au fur et à mesure »): said on its tile with ✓ or ○, settled by its button.
public struct AddOnNeed: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var done: Bool
    /// The button that settles it, while it is not done.
    public var action: AddOnAction?
    public var button: String?
    /// What to know when hub cannot do it for Paul.
    public var note: String?

    public init(_ id: String, _ title: String, done: Bool, action: AddOnAction? = nil, button: String? = nil, note: String? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.action = done ? nil : action
        self.button = done ? nil : button
        self.note = done ? nil : note
    }
}

/// Where an add-on is: to install, everything settled, or something missing.
public enum AddOnState: Equatable, Sendable {
    case notInstalled
    case ready
    case missing(Int)

    public var text: String {
        switch self {
        case .notInstalled: "À installer"
        case .ready: "Tout est réglé"
        case .missing(let count): count == 1 ? "Il manque 1 chose" : "Il manque \(count) choses"
        }
    }
}

public enum AddOnNeeds {
    /// What the add-on needs on this Mac, in the order Paul settles it.
    public static func list(_ addOn: AddOn, _ facts: AddOnFacts) -> [AddOnNeed] {
        switch addOn {
        case .projects, .inspiration:
            []
        case .meetings:
            [model(facts), microphone(facts),
             AddOnNeed("reunions", "Le son des autres et Dia", done: facts.meetingsChecked, action: .openDiagnostic, button: "Vérifier")]
        case .dictation:
            [model(facts), microphone(facts),
             AddOnNeed("accessibilite", "L'Accessibilité, pour écrire dans tes apps", done: facts.accessibility, action: .askAccessibility,
                       button: "Autoriser")]
        case .calendar:
            [google(facts)]
        case .mails:
            [google(facts),
             AddOnNeed("boite", "Les mails autorisés sur un compte", done: facts.mailboxes > 0, action: .openGoogleAccounts,
                       button: "Ouvrir Comptes Google")]
        case .colin:
            [AddOnNeed("claude", "Claude Code sur ce Mac", done: facts.claudeFound,
                       note: "Installe Claude Code et connecte ton compte, puis relance hub."),
             AddOnNeed("marche", "Colin mis en marche", done: facts.colinOn, action: .openColin, button: "Ouvrir ses réglages")]
        case .vigie:
            [AddOnNeed("moteur", "Le moteur de Vigie sur ce Mac", done: facts.vigieInstalled,
                       note: "Il vient avec l'app Vigie : installe-la. hub le posera lui-même à une prochaine étape."),
             AddOnNeed("moteur-marche", "Le moteur en marche", done: facts.vigieInstalled && facts.vigieRunning,
                       note: facts.vigieInstalled ? "Relance-le depuis la page Vigie de hub." : nil)]
        case .iphone:
            [AddOnNeed("icloud", "iCloud sur ce Mac", done: facts.iCloud, note: "Connecte ce Mac à iCloud dans Réglages Système."),
             AddOnNeed("relie", "Un iPhone relié", done: facts.phones > 0, action: .openPhone, button: "Relier un iPhone")]
        }
    }

    public static func state(installed: Bool, needs: [AddOnNeed]) -> AddOnState {
        guard installed else { return .notInstalled }
        let missing = needs.filter { !$0.done }.count
        return missing == 0 ? .ready : .missing(missing)
    }

    /// Everything the installed add-ons need, once each, with the tools it serves (21/11, Paul: « une page avec tout ce
    /// qu'il y a à accepter… pour quel outil c'est nécessaire… voir tout ce qui est connecté »): the Diagnostic's list.
    public static func connections(installed: Set<AddOn>, _ facts: AddOnFacts) -> [AddOnConnection] {
        var result: [AddOnConnection] = []
        for addOn in AddOn.allCases where installed.contains(addOn) {
            for need in list(addOn, facts) {
                if let index = result.firstIndex(where: { $0.need.id == need.id }) {
                    result[index].tools.append(addOn)
                } else {
                    result.append(AddOnConnection(need: need, tools: [addOn]))
                }
            }
        }
        return result
    }

    /// The first thing to settle, with a button: the tile's main gesture.
    public static func next(_ needs: [AddOnNeed]) -> AddOnNeed? {
        needs.first { !$0.done && $0.action != nil }
    }

    static func model(_ facts: AddOnFacts) -> AddOnNeed {
        AddOnNeed("modele", "Le modèle de transcription", done: facts.modelsReady, note: "Il se télécharge à l'installation (1,6 Go).")
    }

    static func microphone(_ facts: AddOnFacts) -> AddOnNeed {
        AddOnNeed("micro", "Le micro", done: facts.microphone == .granted, action: .askMicrophone,
                  button: facts.microphone == .denied ? "Ouvrir Réglages Système" : "Autoriser")
    }

    static func google(_ facts: AddOnFacts) -> AddOnNeed {
        AddOnNeed("google", "Un compte Google", done: facts.googleAccounts > 0, action: facts.googleKey ? .connectGoogle : nil,
                  button: facts.googleKey ? "Connecter un compte" : nil,
                  note: facts.googleKey ? nil : "La clé Google de hub manque sur ce Mac : elle se pose une fois, hors de l'app.")
    }
}

/// A need shared by the tools that ask for it.
public struct AddOnConnection: Identifiable, Equatable, Sendable {
    public var need: AddOnNeed
    public var tools: [AddOn]
    public var id: String { need.id }

    /// « Pour Réunions et Dictée ».
    public var forWhom: String {
        let names = tools.map(\.title)
        guard names.count > 1 else { return "Pour " + (names.first ?? "") }
        return "Pour " + names.dropLast().joined(separator: ", ") + " et " + names[names.count - 1]
    }
}
