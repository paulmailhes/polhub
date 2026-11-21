import Foundation

/// What hub can do, installed one by one (20/11, « le socle des add-ons »): Réglages › Add-ons lists them in this
/// order. The rest of the app follows the installed ones: what is not installed shows nowhere and does not run.
public enum AddOn: String, CaseIterable, Codable, Sendable {
    case projects = "projets"
    case meetings = "reunions"
    /// The Dictée (20/11): Paul talks, his words are written where his cursor is; Réunions' model.
    case dictation = "dictee"
    case calendar = "calendrier"
    case mails = "mails"
    case inspiration = "inspiration"
    case colin = "colin"
    /// Vigie (21/11): it watches over Claude Code; hub shows what its engine sees.
    case vigie = "vigie"
    case iphone = "iphone"

    /// Its name, as the page and the sidebar say it.
    public var title: String {
        switch self {
        case .projects: "Projets"
        case .meetings: "Réunions"
        case .dictation: "Dictée"
        case .calendar: "Calendrier"
        case .mails: "Mails"
        case .inspiration: "Inspiration"
        case .colin: "Colin"
        case .vigie: "Vigie"
        case .iphone: "iPhone"
        }
    }

    /// What it needs installed with it: the Google accounts live with the agenda; Colin reads the mails and the agenda.
    public var requires: [AddOn] {
        switch self {
        case .mails: [.calendar]
        case .colin: [.mails, .calendar]
        case .projects, .meetings, .dictation, .calendar, .inspiration, .vigie, .iphone: []
        }
    }
}

/// The sets of add-ons an installation or a removal leaves.
public enum AddOns {
    /// The add-on and what it needs, all the way down.
    public static func installing(_ addOn: AddOn, into installed: Set<AddOn>) -> Set<AddOn> {
        var result = installed
        var waiting = [addOn]
        while let next = waiting.popLast() {
            result.insert(next)
            waiting += next.requires.filter { !result.contains($0) }
        }
        return result
    }

    /// Without the add-on and without what needs it, all the way up.
    public static func uninstalling(_ addOn: AddOn, from installed: Set<AddOn>) -> Set<AddOn> {
        var result = installed
        var waiting = [addOn]
        while let next = waiting.popLast() {
            result.remove(next)
            waiting += result.filter { $0.requires.contains(next) }
        }
        return result
    }

    /// The others an installation brings, in the page's order: what the confirmation names.
    public static func added(by addOn: AddOn, to installed: Set<AddOn>) -> [AddOn] {
        let after = installing(addOn, into: installed)
        return AddOn.allCases.filter { $0 != addOn && after.contains($0) && !installed.contains($0) }
    }

    /// The others a removal takes, in the page's order.
    public static func removed(by addOn: AddOn, from installed: Set<AddOn>) -> [AddOn] {
        let after = uninstalling(addOn, from: installed)
        return AddOn.allCases.filter { $0 != addOn && installed.contains($0) && !after.contains($0) }
    }
}

/// The installed add-ons, kept in the app's settings. Without the key (a version before 0.59.0, or a command that
/// cannot read the app's settings) every add-on counts as installed: nothing disappears by mistake.
public struct AddOnStore: @unchecked Sendable {
    public static let key = "addOns.installes"
    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The app's own settings, as the command line `hub mcp` reads them (the production app's identifier).
    public static var app: AddOnStore {
        AddOnStore(defaults: UserDefaults(suiteName: "fr.paulmailhes.polhub") ?? .standard)
    }

    public var installed: Set<AddOn> {
        guard let names = defaults.array(forKey: Self.key) as? [String] else { return Set(AddOn.allCases) }
        return Set(names.compactMap(AddOn.init(rawValue:)))
    }

    public func save(_ set: Set<AddOn>) {
        defaults.set(AddOn.allCases.filter(set.contains).map(\.rawValue), forKey: Self.key)
    }

    /// The add-ons just installed, whose guide opens after the relaunch (21/11): « ce qu'il leur faut ». `welcome`: the
    /// installation came from the Bienvenue, whose last step the guide is.
    public func setPendingGuide(_ addOns: [AddOn], welcome: Bool) {
        defaults.set(addOns.map(\.rawValue), forKey: Self.guideKey)
        defaults.set(welcome, forKey: Self.guideWelcomeKey)
    }

    /// The guide to open, once: reading it forgets it.
    public func takePendingGuide() -> (addOns: [AddOn], welcome: Bool) {
        let names = defaults.stringArray(forKey: Self.guideKey) ?? []
        let welcome = defaults.bool(forKey: Self.guideWelcomeKey)
        defaults.removeObject(forKey: Self.guideKey)
        defaults.removeObject(forKey: Self.guideWelcomeKey)
        return (names.compactMap(AddOn.init(rawValue:)), welcome)
    }

    static let guideKey = "addOns.guide"
    static let guideWelcomeKey = "addOns.guideBienvenue"

    /// Once, at the first launch that knows the add-ons: a base already there has them all, a new one none.
    public func settle(baseExists: Bool) {
        guard defaults.object(forKey: Self.key) == nil else { return }
        save(baseExists ? Set(AddOn.allCases) : [])
    }
}
