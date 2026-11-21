import AppKit
import Dictation
import Foundation
import HubDesign
import Testing
@testable import MeetingsUI

/// 21/11 (Paul : « je ne vois rien apparaître… beaucoup plus expliqué ») : la fenêtre de la Dictée dit toujours ce qui se
/// passe — le micro qui s'ouvre, l'écoute, la relecture et son avancement, où le texte est allé, ou pourquoi rien.
@Suite struct DictationWindowTests {
    @Test func theMicrophoneOpeningIsSaidBeforeListening() {
        let opening = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: false))
        #expect(opening.mark == .opening && opening.title == "Le micro s'ouvre…")
        #expect(opening.hint == "⌥ droite pour finir · Échap pour annuler")
        let listening = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: true))
        #expect(listening.mark == .listening && listening.title == "Je t'écoute")
        #expect(listening.words == nil && listening.placeholder == "Parle : tes mots s'écrivent ici.")
    }

    @Test func theWordsComeAsTheyAreSaid() {
        let content = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: true, partial: "Bonjour Camille"))
        #expect(content.words == "Bonjour Camille" && content.progress == nil)
        let hidden = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: true, partial: "Bonjour", liveText: false))
        #expect(hidden.words == nil && hidden.placeholder == "Parle, puis appuie de nouveau.")
    }

    @Test func theKeysFollowTheWayTheKeyWorks() {
        let held = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: true, mode: .hold))
        #expect(held.hint == "Relâche pour finir · Échap pour annuler")
        let other = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: true, key: "Fn"))
        #expect(other.hint == "Fn pour finir · Échap pour annuler")
    }

    @Test func aLongSilenceSaysWhenItFinishes() {
        let content = DictationWindowContent(DictationWindowState(phase: .listening, micOpen: true, partial: "Voilà", silenceLeft: 3))
        #expect(content.hint == "Silence : je finis dans 3 s")
    }

    @Test func theFinalWritingShowsItsProgress() {
        let writing = DictationWindowContent(DictationWindowState(phase: .writing, micOpen: true, partial: "Bonjour Camille", progress: 0.4))
        #expect(writing.mark == .writing && writing.title == "J'écris tes derniers mots…")
        #expect(writing.words == "Bonjour Camille" && writing.progress == 0.4)
        #expect(writing.hint == "Le texte arrive là où tu écrivais")
        let loading = DictationWindowContent(DictationWindowState(phase: .writing, whisperLoaded: false, progress: 0.4))
        #expect(loading.title == "Whisper se charge, puis j'écris…" && loading.progress == nil)
        #expect(DictationWindowContent(DictationWindowState(phase: .writing, progress: 7)).progress == 1)
    }

    @Test func theEndSaysWhereTheTextWent() {
        let pasted = DictationWindowContent(DictationWindowState(phase: .ready, outcome: .pasted(app: "Mail", text: "Bonjour Camille.")))
        #expect(pasted.mark == .done && pasted.title == "Collé dans Mail" && pasted.words == "Bonjour Camille.")
        #expect(DictationWindowContent(DictationWindowState(phase: .ready, outcome: .pasted(app: nil, text: "Oui"))).title == "Collé")
        let copied = DictationWindowContent(DictationWindowState(phase: .ready, outcome: .copied(text: "Oui")))
        #expect(copied.title == "Copié : colle-le avec ⌘V" && copied.hint?.contains("Accessibilité") == true)
    }

    @Test func nothingHeardAndNotReadyAreSaidToo() {
        let nothing = DictationWindowContent(DictationWindowState(phase: .ready, outcome: .nothing))
        #expect(nothing.mark == .notice && nothing.title == "Je n'ai rien entendu")
        let early = DictationWindowContent(DictationWindowState(phase: .starting, outcome: .notReady("La Dictée démarre…")))
        #expect(early.mark == .notice && early.title == "La Dictée démarre…" && early.hint == "Réessaie dans un instant")
        let broken = DictationWindowContent(DictationWindowState(phase: .ready, outcome: .problem("Le micro ne s'ouvre pas.")))
        #expect(broken.mark == .problem && broken.title == "Le micro ne s'ouvre pas.")
    }

    /// 21/11 (Paul : « on dirait qu'il veut garder le début de la phrase… il met des trois petits points au milieu… faut
    /// que ça continue de défiler le paragraphe et que ça coupe le début ») : la fenêtre montre la fin de ce qui est dit,
    /// en mots entiers, sur ses trois lignes ; les premiers mots s'en vont.
    @Test func theWordsScrollAndKeepTheirEnd() {
        let font = NSFont.systemFont(ofSize: TextSize.rowTitle)
        let limit = DictationWords.height(lines: 3, font: font)
        let long = (1...200).map { "mot\($0)" }.joined(separator: " ")
        let shown = DictationWords.tail(long, width: 500, lines: 3)
        #expect(shown.cut && long.hasSuffix(shown.text) && shown.text.hasPrefix("mot") && shown.text.hasSuffix("mot200"))
        #expect(DictationWords.height(of: shown.text, width: 500, font: font) <= limit)
        // As many as hold: one word more would not.
        let words = long.split(separator: " ")
        let first = words.count - shown.text.split(separator: " ").count
        #expect(DictationWords.height(of: words[(first - 1)...].joined(separator: " "), width: 500, font: font) > limit)
        let short = DictationWords.tail("Bonjour Camille", width: 500, lines: 3)
        #expect(!short.cut && short.text == "Bonjour Camille")
    }

    /// A new dictation hides what the one before said.
    @Test func aNewDictationForgetsTheLastOutcome() {
        let state = DictationWindowState(phase: .listening, micOpen: true, outcome: .pasted(app: "Mail", text: "Avant"))
        #expect(DictationWindowContent(state).title == "Je t'écoute")
    }
}
