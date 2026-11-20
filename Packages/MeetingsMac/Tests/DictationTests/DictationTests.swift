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
    /// 20/11 au soir (Paul) : un appui commence, un appui arrête ; on ne reste pas appuyé.
    @Test func onePressStartsAndOnePressFinishes() {
        var gesture = KeyGesture(mode: .toggle)
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 0.1) == .none)
        #expect(gesture.tick(at: 9) == .none)
        #expect(gesture.keyDown(at: 10) == .finish)
        #expect(gesture.keyUp(at: 10.1) == .none)
        #expect(gesture.state == .idle)
    }

    @Test func holdingTalksAndReleasingPastes() {
        var gesture = KeyGesture(mode: .hold)
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 1.2) == .finish)
        #expect(gesture.state == .idle)
    }

    @Test func holdModeTwoTapsTalkHandsFreeUntilATap() {
        var gesture = KeyGesture(mode: .hold)
        #expect(gesture.keyDown(at: 0) == .start)
        #expect(gesture.keyUp(at: 0.1) == .none)
        #expect(gesture.keyDown(at: 0.3) == .none)
        #expect(gesture.keyUp(at: 0.35) == .none)
        #expect(gesture.state == .handsFree)
        #expect(gesture.keyDown(at: 6) == .finish)
        #expect(gesture.keyUp(at: 6.1) == .none)
        #expect(gesture.state == .idle)
    }

    @Test func holdModeForgetsASingleTap() {
        var gesture = KeyGesture(mode: .hold)
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        #expect(gesture.tick(at: 0.3) == .none)
        #expect(gesture.tick(at: 0.6) == .cancel)
    }

    /// Both: a short press starts and a press finishes; held long, it finishes on release.
    @Test func bothModeTogglesOrHolds() {
        var tapped = KeyGesture(mode: .hybrid)
        #expect(tapped.keyDown(at: 0) == .start)
        #expect(tapped.keyUp(at: 0.1) == .none)
        #expect(tapped.keyDown(at: 5) == .finish)
        var held = KeyGesture(mode: .hybrid)
        #expect(held.keyDown(at: 0) == .start)
        #expect(held.keyUp(at: 2) == .finish)
    }

    /// The key with another key types a character: nothing is dictated, whatever the mode.
    @Test func theKeyUsedForTypingCancels() {
        for mode in KeyGesture.Mode.allCases {
            var gesture = KeyGesture(mode: mode)
            _ = gesture.keyDown(at: 0)
            #expect(gesture.otherKey() == .cancel, "\(mode)")
            #expect(gesture.keyUp(at: 0.5) == .none, "\(mode)")
            #expect(gesture.state == .idle, "\(mode)")
        }
    }

    /// Typing while a toggled dictation listens does not stop it.
    @Test func typingDuringAToggledDictationGoesOn() {
        var gesture = KeyGesture(mode: .toggle)
        _ = gesture.keyDown(at: 0)
        _ = gesture.keyUp(at: 0.1)
        #expect(gesture.otherKey() == .none)
        #expect(gesture.state == .listening)
    }

    @Test func escapeCancelsAnything() {
        for mode in KeyGesture.Mode.allCases {
            var gesture = KeyGesture(mode: mode)
            _ = gesture.keyDown(at: 0)
            _ = gesture.keyUp(at: 0.1)
            _ = gesture.keyDown(at: 0.2)
            _ = gesture.keyUp(at: 0.25)
            _ = gesture.keyDown(at: 3)
            _ = gesture.keyUp(at: 3.1)
            var fresh = KeyGesture(mode: mode)
            _ = fresh.keyDown(at: 0)
            #expect(fresh.escape() == .cancel && fresh.state == .ignoringRelease, "\(mode)")
            #expect(fresh.escape() == .none)
        }
    }
}

@Suite struct DictationProtocolTests {
    @Test func commandsAndEventsTravelAsOneLineOfJSON() throws {
        let listening = DictationListening(language: "fr", prompt: "hub, Vigie", paragraphPause: 3, microphones: ["casque", "interne"],
                                           keepSoundAt: "/tmp/son.m4a", source: "/tmp/essai.wav")
        for command in [DictationCommand.start(listening), .stop, .cancel, .file(id: "a", path: "/tmp/memo.m4a", listening: listening)] {
            let line = try DictationWire.line(command)
            #expect(!line.contains("\n"))
            #expect(try DictationWire.read(DictationCommand.self, line) == command)
        }
        for event in [DictationEvent.hello, .ready, .listening, .level(0.4), .partial("Bonjour"), .progress(0.5), .final(text: "Bonjour.", seconds: 1.5),
                      .transcribed(id: "a", text: "Premier.\n\nSecond.", seconds: 62), .fileFailed(id: "a", reason: "illisible"), .failed("micro")] {
            #expect(try DictationWire.read(DictationEvent.self, try DictationWire.line(event)) == event)
        }
    }
}

/// 20/11 au soir (Paul) : les nombres en chiffres, à partir de 10 ou devant une unité ; « un » reste en lettres.
@Suite struct DictationNumbersTests {
    @Test func numbersFromTenAreWrittenInDigits() {
        #expect(DictationNumbers.digits("Il y a vingt-cinq personnes et deux chiens.") == "Il y a 25 personnes et deux chiens.")
        #expect(DictationNumbers.digits("En deux mille vingt-six, trois cent douze clients.") == "En 2026, 312 clients.")
        #expect(DictationNumbers.digits("quatre-vingt-dix-neuf et soixante et onze et dix-sept") == "99 et 71 et 17")
        #expect(DictationNumbers.digits("mille deux cents et quatre-vingts") == "1200 et 80")
        #expect(DictationNumbers.digits("Vingt-cinq personnes.") == "25 personnes.")
    }

    @Test func smallNumbersStayInWordsUnlessAUnitFollows() {
        #expect(DictationNumbers.digits("On se cale un point demain, les deux.") == "On se cale un point demain, les deux.")
        #expect(DictationNumbers.digits("Ça dure deux heures et coûte trois euros.") == "Ça dure 2 h et coûte 3 €.")
        #expect(DictationNumbers.digits("Dans une heure.") == "Dans une heure.")
        #expect(DictationNumbers.digits("deux trois fois") == "deux trois fois")
    }

    @Test func timesMoneyPercentsAndDecimals() {
        #expect(DictationNumbers.digits("On se voit à dix heures trente.") == "On se voit à 10 h 30.")
        #expect(DictationNumbers.digits("à dix heures et demie, à neuf heures moins le quart") == "à 10 h 30, à 8 h 45")
        #expect(DictationNumbers.digits("à quatorze heures cinq") == "à 14 h 05")
        #expect(DictationNumbers.digits("Ça coûte vingt-cinq euros cinquante.") == "Ça coûte 25,50 €.")
        #expect(DictationNumbers.digits("vingt pour cent de trois virgule cinq") == "20 % de 3,5")
        #expect(DictationNumbers.digits("Rendez-vous à 10 heures 30, pour 12 euros.") == "Rendez-vous à 10 h 30, pour 12 €.")
        #expect(DictationNumbers.digits("La facture part à 10h30, pour 25 euros, le point à 9h.") == "La facture part à 10 h 30, pour 25 €, le point à 9 h.")
    }

    @Test func separateNumbersStaySeparate() {
        #expect(DictationNumbers.digits("dix douze") == "10 12")
        #expect(DictationNumbers.digits("vingt, trente") == "20, 30")
        #expect(DictationNumbers.digits("Un heureux hasard.") == "Un heureux hasard.")
    }
}

/// 20/11 au soir (Paul) : « à la ligne », « virgule »… dits ; pas de point final sur une phrase ; les « euh » au choix ;
/// les paragraphes gardés.
@Suite struct DictationRulesTests {
    let spoken = DictationRules(fillers: true, spokenPunctuation: true, digits: false, dropFinalPeriod: false)

    @Test func spokenPunctuationBecomesSigns() {
        #expect(DictationText.clean("Bonjour, à la ligne, je voulais te dire merci.", replacements: [], rules: spoken)
            == "Bonjour\nJe voulais te dire merci.")
        #expect(DictationText.clean("Premier point nouveau paragraphe deuxième point.", replacements: [], rules: spoken)
            == "Premier point\n\nDeuxième point.")
        #expect(DictationText.clean("Tu viens point d'interrogation on part bientôt.", replacements: [], rules: spoken)
            == "Tu viens ? On part bientôt.")
        #expect(DictationText.clean("Les pommes virgule les poires point d'exclamation", replacements: [], rules: spoken)
            == "Les pommes, les poires !")
        #expect(DictationText.clean("Il a dit ouvrez les guillemets bonjour fermez les guillemets.", replacements: [], rules: spoken)
            == "Il a dit « bonjour ».")
        #expect(DictationText.clean("Merci point à la ligne à demain.", replacements: [], rules: spoken) == "Merci.\nÀ demain.")
    }

    @Test func twoPointsToSeeStayWords() {
        #expect(DictationText.clean("On a deux points à voir.", replacements: [], rules: spoken) == "On a deux points à voir.")
    }

    @Test func oneSentenceLosesItsFinalPeriod() {
        let chat = DictationRules(fillers: true, spokenPunctuation: false, digits: false, dropFinalPeriod: true)
        #expect(DictationText.clean("Ouvre le projet hub et lance Vigie.", replacements: [], rules: chat) == "Ouvre le projet hub et lance Vigie")
        #expect(DictationText.clean("Ça va ? Moi oui.", replacements: [], rules: chat) == "Ça va ? Moi oui.")
        #expect(DictationText.clean("Tu viens ?", replacements: [], rules: chat) == "Tu viens ?")
        #expect(DictationText.clean("Et ainsi de suite...", replacements: [], rules: chat) == "Et ainsi de suite...")
    }

    @Test func fillersCanStay() {
        let raw = DictationRules(fillers: false, spokenPunctuation: false, digits: false, dropFinalPeriod: false)
        #expect(DictationText.clean("Euh, je voudrais un devis.", replacements: [], rules: raw) == "Euh, je voudrais un devis.")
    }

    @Test func paragraphsStayAndStartWithACapital() {
        #expect(DictationText.clean("Premier sujet.\n\nEuh, deuxième sujet.", replacements: [], rules: .plain)
            == "Premier sujet.\n\nDeuxième sujet.")
    }

    @Test func theDefaultsWriteDigitsAndSpokenSigns() {
        #expect(DictationText.clean("Rendez-vous à dix heures trente, à la ligne, merci.", replacements: [], rules: .standard)
            == "Rendez-vous à 10 h 30\nMerci.")
    }
}

/// 20/11 au soir (Paul) : un paragraphe après une longue pause, « pour que ça change de sujet ».
@Suite struct DictationParagraphsTests {
    static func voice(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 0.07) * 0.3) }
    }

    static func quiet(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * 16_000)).map { Float(sin(Double($0) * 1.3) * 0.001) }
    }

    @Test func onlyTheLongSilencesBetweenWordsArePauses() {
        let samples = Self.quiet(2) + Self.voice(1) + Self.quiet(3.5) + Self.voice(1) + Self.quiet(0.8) + Self.voice(1) + Self.quiet(4)
        let pauses = DictationParagraphs.pauses(samples, longerThan: 3)
        #expect(pauses.count == 1)
        #expect(abs((pauses.first ?? 0) - 4.75) < 0.1)
        #expect(DictationParagraphs.pauses(Self.quiet(5), longerThan: 3).isEmpty)
    }

    @Test func aParagraphStartsAtThePieceAfterEachPause() {
        let pieces = [DictationParagraphs.Piece(text: " Premier sujet.", start: 0, end: 2),
                      DictationParagraphs.Piece(text: "On continue.", start: 2.1, end: 2.6),
                      DictationParagraphs.Piece(text: "Deuxième sujet.", start: 3.9, end: 7.5)]
        #expect(DictationParagraphs.join(pieces, breaks: [4.2]) == "Premier sujet. On continue.\n\nDeuxième sujet.")
        #expect(DictationParagraphs.join(pieces, breaks: []) == "Premier sujet. On continue. Deuxième sujet.")
        #expect(DictationParagraphs.join(pieces, breaks: [99]) == "Premier sujet. On continue. Deuxième sujet.")
    }
}

/// 20/11 au soir (Paul) : en « appuyer, parler, appuyer », la dictée finit seule après un long silence.
@Suite struct SilenceWatchTests {
    @Test func aLongSilenceFinishes() {
        var watch = SilenceWatch(after: 10, startedAt: 0)
        let heard = [(0.4, 1.0), (0.01, 6.0), (0.3, 8.0), (0.01, 17.9), (0.01, 18.1)].map { watch.hear($0.0, at: $0.1) }
        #expect(heard == [false, false, false, false, true])
    }

    @Test func nothingSaidFinishesToo() {
        var watch = SilenceWatch(after: 5, startedAt: 100)
        let heard = [(0.0, 104.0), (0.0, 105.1)].map { watch.hear($0.0, at: $0.1) }
        #expect(heard == [false, true])
    }

    /// 21/11 : la fenêtre compte les trois dernières secondes avant l'arrêt.
    @Test func theSecondsLeftAreCounted() {
        var watch = SilenceWatch(after: 10, startedAt: 0)
        _ = watch.hear(0.4, at: 2)
        #expect(watch.remaining(at: 2) == 10 && watch.remaining(at: 9.5) == 2.5 && watch.remaining(at: 30) == 0)
    }
}
