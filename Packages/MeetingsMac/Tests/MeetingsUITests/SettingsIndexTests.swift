import Domain
import Foundation
import Testing
@testable import MeetingsUI

/// 21/11 (Paul : « moins de pages… une barre de recherche pour rechercher des réglages ») : la recherche trouve un
/// réglage par ses mots, sans accents ni majuscules, sur les pages qui existent ; le Diagnostic dit ce que chaque outil
/// demande, une fois, pour qui.
@Suite struct SettingsIndexTests {
    let everything = Set(SettingsPane.allCases)

    func titles(_ query: String, in panes: Set<SettingsPane>? = nil) -> [String] {
        SettingsIndex.search(query, in: panes ?? everything).map { "\($0.pane.title) › \($0.title)" }
    }

    @Test func aSettingIsFoundByItsWordsWhateverTheAccents() {
        #expect(titles("paragraphe") == ["Dictée › Paragraphes"])
        #expect(titles("RAPPEL").contains("Calendrier › Rappels avant un rendez-vous"))
        #expect(titles("mise a jour").contains("Général › Installer automatiquement les mises à jour"))
        #expect(titles("ecran") == ["Calendrier › Carte qui reste à l'écran avant une visio"])
        #expect(titles("bluetooth") == ["Dictée › Micros"])
    }

    @Test func everyWordTypedMustBeThere() {
        #expect(titles("son mac") == ["Dictée › Couper le son du Mac"])
        #expect(titles("notification mail").contains("Mails › Nouveau mail dans la Boîte de réception"))
        #expect(titles("zzz").isEmpty && titles("   ").isEmpty)
    }

    @Test func onlyThePagesThereAreSearched() {
        #expect(titles("paragraphe", in: [.general, .diagnostic]).isEmpty)
        #expect(titles("micro", in: [.diagnostic]) == ["Diagnostic › Micro"])
    }

    /// The notifications are in each tool since 21/11: none is left without its page.
    @Test func theNotificationsAreInTheirTools() {
        let notices = SettingsIndex.entries.filter { $0.words.contains("notification") && $0.title != $0.pane.title }.map(\.pane)
        #expect(Set(notices) == [.meetings, .calendar, .mails, .colin, .general])
        #expect(!SettingsPane.allCases.map(\.rawValue).contains("notifications") && !SettingsPane.allCases.map(\.rawValue).contains("updates"))
    }

    @Test func everyPageHasItsOwnEntry() {
        for pane in SettingsPane.allCases {
            #expect(SettingsIndex.entries.contains { $0.pane == pane && $0.title == pane.title }, "\(pane)")
        }
    }

    @Test func hubsOwnPagesFollowTheAddOns() {
        #expect(SettingsPane.hubPanes(hasAgenda: true) == [.accounts, .diagnostic, .general])
        #expect(SettingsPane.hubPanes(hasAgenda: false) == [.diagnostic, .general])
        #expect(SettingsPane.general.lines == [.journal] && SettingsPane.diagnostic.parent == nil && SettingsPane.journal.parent == .general)
    }

    @Test func eachNeedIsListedOnceWithTheToolsItServes() {
        var facts = AddOnFacts()
        facts.microphone = .notAsked
        facts.googleAccounts = 0
        let connections = AddOnNeeds.connections(installed: [.meetings, .dictation, .calendar, .mails, .vigie], facts)
        #expect(connections.map(\.id) == ["modele", "micro", "reunions", "accessibilite", "google", "boite", "moteur", "moteur-marche"])
        let micro = try? #require(connections.first { $0.id == "micro" })
        #expect(micro?.tools == [.meetings, .dictation] && micro?.forWhom == "Pour Réunions et Dictée" && micro?.need.done == false)
        #expect(connections.first { $0.id == "google" }?.forWhom == "Pour Calendrier et Mails")
        #expect(AddOnNeeds.connections(installed: [.projects, .inspiration], facts).isEmpty)
    }
}
