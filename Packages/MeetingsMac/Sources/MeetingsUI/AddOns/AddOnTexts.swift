import Domain

/// What Réglages › Add-ons says (20/11): one short sentence each, « hub » in lowercase.
public enum AddOnTexts {
    public static let busy = "Pas pendant une réunion : réessaie quand elle est finie."
    public static let installing = "hub se relance pour l'installer."
    public static let removing = "hub se relance pour le retirer."
    public static let keepsData = "Ses données restent : le réinstaller le remet comme avant."
    public static let permissions = "Les autorisations données à macOS se retirent dans Réglages Système › Confidentialité."
    /// Réunions and Dictée share their model: it goes with the last of them.
    public static func takingModel(_ addOn: AddOn, installed: Set<AddOn>) -> String? {
        let other: AddOn = addOn == .meetings ? .dictation : .meetings
        guard [.meetings, .dictation].contains(addOn), !installed.contains(other) else { return nil }
        return addOn == .meetings ? "Désinstaller Réunions efface aussi son modèle (1,6 Go). Tes réunions enregistrées restent."
            : "Désinstaller Dictée efface aussi son modèle (1,6 Go). Ton historique et ta mémoire restent."
    }
    public static let needsClaude = "Installe d'abord Claude Code sur ce Mac."
    public static let choose = "Choisis tes add-ons : hub ne montre et ne fait que ce que tu installes."

    /// What it does, as the design says it.
    public static func summary(_ addOn: AddOn) -> String {
        switch addOn {
        case .projects: "Le kanban et la page de chaque projet"
        case .meetings: "Tes Meet enregistrés, transcrits et résumés"
        case .dictation: "Parle : tes mots s'écrivent là où est ton curseur"
        case .calendar: "Ton agenda Google"
        case .mails: "Tes boîtes Gmail"
        case .inspiration: "Sites, branding et mock-ups"
        case .colin: "L'agent de l'Accueil"
        case .iphone: "L'app iPhone, même Mac éteint"
        }
    }

    /// What it asks for when it is installed; nil when nothing.
    public static func needs(_ addOn: AddOn) -> String? {
        switch addOn {
        case .meetings: "1,6 Go à télécharger"
        case .dictation: "le modèle de Réunions (1,6 Go), l'Accessibilité"
        case .calendar, .mails: "un compte Google"
        case .colin: "Claude Code sur ce Mac"
        case .iphone: "iCloud"
        case .projects, .inspiration: nil
        }
    }

    /// The help under its name: what it does, then what it asks for.
    public static func help(_ addOn: AddOn) -> String {
        [summary(addOn), needs(addOn)].compactMap { $0 }.joined(separator: " · ")
    }

    /// « Mails », « Mails et Calendrier », « Mails, Calendrier et Colin ».
    static func list(_ addOns: [AddOn]) -> String {
        let names = addOns.map(\.title)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " et " + names[names.count - 1]
    }

    /// « Colin a besoin de Mails et de Calendrier : ils s'installent aussi. »
    static func bringing(_ addOn: AddOn, _ others: [AddOn]) -> String {
        let names = others.map { "de " + $0.title }
        let joined = names.count > 1 ? names.dropLast().joined(separator: ", ") + " et " + names[names.count - 1] : names.first ?? ""
        return "\(addOn.title) a besoin \(joined) : \(others.count == 1 ? "il s'installe" : "ils s'installent") aussi."
    }

    /// « Désinstaller Calendrier désinstalle aussi Mails et Colin. »
    static func taking(_ addOn: AddOn, _ others: [AddOn]) -> String {
        "Désinstaller \(addOn.title) désinstalle aussi \(list(others))."
    }
}
