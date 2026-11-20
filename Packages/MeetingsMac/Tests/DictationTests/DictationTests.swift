import Foundation
import Testing
@testable import Dictation

/// 20/11 : la Dictée. Tes mots, bien ponctués, sans les « euh », avec ta mémoire ; la touche qu'on tient, ou deux
/// appuis pour parler mains libres ; jamais quand ⌥ sert à taper un caractère.
@Suite struct DictationTextTests {
    @Test func fillersGoAndSpacesStayRight() {
        #expect(DictationText.clean("Euh, je voudrais, euh, un devis.", replacements: []) == "Je voudrais un devis.")
        #expect(DictationText.clean("  hum   on se voit   demain ? ", replacements: []) == "On se voit demain ?")
        #expect(DictationText.clean("Un heureux hasard.", replacements: []) == "Un heureux hasard.")
    }

    @Test func correctionsReplaceWholeWordsWhateverTheirCase() {
        let corrections = [DictationReplacement(heard: "mythe", written: "Meet"), DictationReplacement(heard: "Paul Hub", written: "hub"),
                           DictationReplacement(heard: "Vigi", written: "Vigie")]
        #expect(DictationText.clean("Lance le Mythe et ouvre paul hub.", replacements: corrections) == "Lance le Meet et ouvre hub.")
        #expect(DictationText.clean("Vigi et Vigilance.", replacements: corrections) == "Vigie et Vigilance.")
    }

    @Test func aPhantomSentenceIsNothing() {
        #expect(DictationText.clean("Sous-titres réalisés par la communauté d'Amara.org", replacements: []).isEmpty)
        #expect(DictationText.clean("Merci d'avoir regardé !", replacements: []).isEmpty)
    }

    @Test func thePromptKeepsTheWordsOnceWithinItsLength() {
        let prompt = DictationPrompt.make(["hub", "Vigie", "hub", "Atelier Exemple", "VIGIE"], limit: 30)
        #expect(prompt == "hub, Vigie, Atelier Exemple")
        #expect(DictationPrompt.make((1...200).map { "Mot\($0)" }, limit: 60).count <= 60)
        #expect(DictationPrompt.make([], limit: 60).isEmpty)
    }
}

@Suite struct KeyGestureTests {
    @Test func holdingTalksAndReleasingPastes() {
        var gesture = KeyGesture()
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 1.2) == .finish)
        #expect(gesture.state == .idle)
    }

    @Test func twoTapsTalkHandsFreeUntilATap() {
        var gesture = KeyGesture()
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 0.1) == .none)
        #expect(gesture.keyDown(at: 0.3) == .none)
        #expect(gesture.keyUp(at: 0.35) == .none)
        #expect(gesture.state == .handsFree)
        #expect(gesture.tick(at: 5) == .none)
        #expect(gesture.keyDown(at: 6) == .finish)
        #expect(gesture.keyUp(at: 6.1) == .none)
        #expect(gesture.state == .idle)
    }

    @Test func aSingleTapIsForgotten() {
        var gesture = KeyGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        #expect(gesture.tick(at: 0.3) == .none)
        #expect(gesture.tick(at: 0.6) == .cancel)
        #expect(gesture.state == .idle)
    }

    /// ⌥ with another key types a character: nothing is dictated.
    @Test func optionUsedForTypingCancels() {
        var gesture = KeyGesture()
        _ = gesture.keyDown(at: 0)
        #expect(gesture.otherKey() == .cancel)
        #expect(gesture.keyUp(at: 0.5) == .none)
        #expect(gesture.state == .idle)
    }

    @Test func escapeCancelsAnything() {
        var gesture = KeyGesture()
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        _ = gesture.keyDown(at: 0.2)
        _ = gesture.keyUp(at: 0.25)
        #expect(gesture.escape() == .cancel && gesture.state == .idle)
        #expect(gesture.escape() == .none)
    }
}

@Suite struct DictationProtocolTests {
    @Test func commandsAndEventsTravelAsOneLineOfJSON() throws {
        let command = DictationCommand.start(language: "fr", prompt: "hub, Vigie")
        let line = try DictationWire.line(command)
        #expect(!line.contains("\n"))
        #expect(try DictationWire.read(DictationCommand.self, line) == command)
        for event in [DictationEvent.ready, .level(0.4), .partial("Bonjour"), .final(text: "Bonjour.", seconds: 1.5), .failed("micro")] {
            #expect(try DictationWire.read(DictationEvent.self, try DictationWire.line(event)) == event)
        }
    }
}
