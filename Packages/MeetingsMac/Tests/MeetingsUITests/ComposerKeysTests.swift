import SwiftUI
import Testing
@testable import MeetingsUI

/// The keys of Colin's bar (the Accueil's pass, 18/11): Return sends, Shift-Return goes to the line, Escape stops an
/// answer; a word being composed (a dictation, an accent) is never sent half-way.
@Suite struct ComposerKeysTests {
    @Test func returnSendsShiftReturnGoesToTheLine() {
        #expect(ComposerKeys.action(key: .return, modifiers: [], composing: false, answering: false) == .send)
        #expect(ComposerKeys.action(key: .return, modifiers: .shift, composing: false, answering: false) == .newline)
        #expect(ComposerKeys.action(key: .return, modifiers: .option, composing: false, answering: false) == .newline)
    }

    /// Review Focus 4.
    @Test func aWordBeingComposedIsNotSent() {
        #expect(ComposerKeys.action(key: .return, modifiers: [], composing: true, answering: false) == .none)
    }

    @Test func escapeStopsAnAnswerOnly() {
        #expect(ComposerKeys.action(key: .escape, modifiers: [], composing: false, answering: true) == .stop)
        #expect(ComposerKeys.action(key: .escape, modifiers: [], composing: false, answering: false) == .none)
    }

    /// While Colin answers, Return does not send a second question.
    @Test func returnWaitsForTheAnswer() {
        #expect(ComposerKeys.action(key: .return, modifiers: [], composing: false, answering: true) == .none)
    }
}
