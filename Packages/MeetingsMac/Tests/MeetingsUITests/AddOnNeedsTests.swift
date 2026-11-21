import Domain
import Foundation
import Testing
@testable import MeetingsUI

/// 21/11 (Paul : « dès qu'on ajoute un add-on, ça dit qu'il faut un compte… qu'on puisse mettre tout ce qu'il faut au fur
/// et à mesure ») : ce qu'il faut à chaque add-on, fait ou non, et le bouton qui le règle.
@Suite struct AddOnNeedsTests {
    @Test func projectsAndInspirationNeedNothing() {
        #expect(AddOnNeeds.list(.projects, AddOnFacts()).isEmpty && AddOnNeeds.list(.inspiration, AddOnFacts()).isEmpty)
        #expect(AddOnNeeds.state(installed: true, needs: []) == .ready)
        #expect(AddOnNeeds.state(installed: false, needs: []) == .notInstalled)
    }

    @Test func mailsNeedAGoogleAccountThenItsMails() {
        var facts = AddOnFacts()
        let needs = AddOnNeeds.list(.mails, facts)
        #expect(needs.map(\.title) == ["Un compte Google", "Les mails autorisés sur un compte"])
        #expect(needs.map(\.done) == [false, false])
        #expect(AddOnNeeds.next(needs)?.button == "Connecter un compte" && AddOnNeeds.next(needs)?.action == .connectGoogle)
        #expect(AddOnNeeds.state(installed: true, needs: needs) == .missing(2))
        facts.googleAccounts = 1
        #expect(AddOnNeeds.next(AddOnNeeds.list(.mails, facts))?.action == .openGoogleAccounts)
        facts.mailboxes = 1
        let done = AddOnNeeds.list(.mails, facts)
        #expect(done.allSatisfy(\.done) && done.allSatisfy { $0.button == nil && $0.action == nil })
        #expect(AddOnNeeds.state(installed: true, needs: done) == .ready)
    }

    @Test func withoutTheGoogleKeyTheAccountSaysWhy() {
        var facts = AddOnFacts()
        facts.googleKey = false
        let need = AddOnNeeds.list(.calendar, facts)[0]
        #expect(need.action == nil && need.button == nil && need.note?.contains("clé Google") == true)
        #expect(AddOnNeeds.next([need]) == nil)
    }

    @Test func theDictationNeedsItsModelTheMicrophoneAndTheAccessibility() {
        var facts = AddOnFacts()
        facts.accessibility = false
        facts.microphone = .denied
        let needs = AddOnNeeds.list(.dictation, facts)
        #expect(needs.map(\.id) == ["modele", "micro", "accessibilite"])
        #expect(needs.map(\.done) == [true, false, false])
        #expect(needs[1].button == "Ouvrir Réglages Système" && needs[2].button == "Autoriser")
        facts.microphone = .notAsked
        #expect(AddOnNeeds.list(.dictation, facts)[1].button == "Autoriser")
        #expect(AddOnNeeds.state(installed: true, needs: needs).text == "Il manque 2 choses")
        #expect(AddOnState.missing(1).text == "Il manque 1 chose" && AddOnState.ready.text == "Tout est réglé")
        #expect(AddOnState.notInstalled.text == "À installer")
    }

    @Test func colinAndTheIPhoneSayWhatHubCannotDo() {
        var facts = AddOnFacts()
        facts.claudeFound = false
        facts.colinOn = false
        facts.iCloud = false
        let colin = AddOnNeeds.list(.colin, facts)
        #expect(colin[0].note?.contains("Claude Code") == true && colin[0].action == nil)
        #expect(AddOnNeeds.next(colin)?.action == .openColin)
        let phone = AddOnNeeds.list(.iphone, facts)
        #expect(phone.map(\.done) == [false, false] && AddOnNeeds.next(phone)?.button == "Relier un iPhone")
        #expect(AddOnAction.openPhone.leavesThePage && !AddOnAction.connectGoogle.leavesThePage)
    }
}
