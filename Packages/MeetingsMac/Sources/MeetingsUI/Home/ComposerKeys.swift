import AppKit
import SwiftUI

/// What a key does in Colin's bar (the Accueil's pass, 18/11).
enum ComposerAction: Equatable {
    case send, newline, stop, none
}

/// The keys of Colin's bar: Return sends, Shift-Return (or Option-Return) goes to the line, Escape stops an answer.
/// A word being composed (a dictation, an accent) is never sent half-way; while Colin answers, Return waits.
enum ComposerKeys {
    static func action(key: KeyEquivalent, modifiers: EventModifiers, composing: Bool, answering: Bool) -> ComposerAction {
        switch key {
        case .return:
            if composing { return .none }
            if modifiers.contains(.shift) || modifiers.contains(.option) { return .newline }
            return answering ? .none : .send
        case .escape:
            return answering ? .stop : .none
        default:
            return .none
        }
    }

    /// Whether the field being typed in holds a word still being composed.
    @MainActor static var composing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}
