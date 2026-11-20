import AppKit
import HubDesign

/// The key held to talk (20/11): ⌥ right by default, changed in Réglages › Dictée.
public enum DictationKey: String, CaseIterable, Sendable {
    case rightOption, rightCommand, rightControl, function

    public var title: String {
        switch self {
        case .rightOption: "⌥ droite"
        case .rightCommand: "⌘ droite"
        case .rightControl: "⌃ droite"
        case .function: "Fn (globe)"
        }
    }

    /// The key's code in a « flags changed » event.
    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .rightControl: 62
        case .function: 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: .option
        case .rightCommand: .command
        case .rightControl: .control
        case .function: .function
        }
    }

    static var current: DictationKey {
        UserDefaults.standard.string(forKey: Preferences.Key.dictationKey).flatMap(DictationKey.init(rawValue:)) ?? .rightOption
    }
}
