import Foundation
import SwiftUI

/// The size of the Kanban's cards (Paul, 14/11: the large ones were too large; a choice in Réglages › Projets).
public enum CardSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "Petites"
        case .medium: "Moyennes"
        case .large: "Grandes"
        }
    }

    public var columnWidth: CGFloat {
        switch self {
        case .small: 220
        case .medium: 256
        case .large: 300
        }
    }

    public var padding: CGFloat {
        switch self {
        case .small: Space.s + 2
        case .medium: Space.m
        case .large: Space.m + 2
        }
    }

    public var todoLines: Int {
        switch self {
        case .small: 2
        case .medium: 2
        case .large: 3
        }
    }

    public var titleFont: Font {
        switch self {
        case .small: .callout.weight(.semibold)
        case .medium: .body.weight(.semibold)
        case .large: .headline
        }
    }
}

/// Every setting of Polhub, its key and its default: the views read them through `@AppStorage(Preferences.Key…)`,
/// the rest through this. New features add theirs here, and a row in Réglages (14/11).
public struct Preferences: @unchecked Sendable {
    public enum Key {
        public static let cardSize = "projets.tailleDesCartes"
        public static let defaultAccount = "agenda.agendaParDefaut"
        public static let eventMinutes = "agenda.dureeParDefaut"
        public static let eventMeet = "agenda.meetParDefaut"
        public static let showWeekend = "agenda.weekEnd"
        public static let dayStartHour = "agenda.debutDeJournee"
        public static let summariesEnabled = "reunions.comptesRendus"
        public static let transcriptionLanguage = "reunions.langue"
    }

    public enum Default {
        public static let eventMinutes = 60
        public static let dayStartHour = 8
        /// `auto` lets the engine detect it.
        public static let transcriptionLanguage = "fr"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var cardSize: CardSize { CardSize(rawValue: defaults.string(forKey: Key.cardSize) ?? "") ?? .medium }
    /// `nil`: the last one used.
    public var defaultAccount: String? { defaults.string(forKey: Key.defaultAccount).flatMap { $0.isEmpty ? nil : $0 } }
    public var eventMinutes: Int { (defaults.object(forKey: Key.eventMinutes) as? Int) ?? Default.eventMinutes }
    public var eventMeet: Bool { (defaults.object(forKey: Key.eventMeet) as? Bool) ?? true }
    public var showWeekend: Bool { (defaults.object(forKey: Key.showWeekend) as? Bool) ?? true }
    public var dayStartHour: Int { (defaults.object(forKey: Key.dayStartHour) as? Int) ?? Default.dayStartHour }
    public var summariesEnabled: Bool { (defaults.object(forKey: Key.summariesEnabled) as? Bool) ?? true }
    /// `nil`: detected by the engine.
    public var transcriptionLanguage: String? {
        let value = defaults.string(forKey: Key.transcriptionLanguage) ?? Default.transcriptionLanguage
        return value == "auto" ? nil : value
    }
}
