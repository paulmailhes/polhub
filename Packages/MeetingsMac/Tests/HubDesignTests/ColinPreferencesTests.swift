import Foundation
import Testing
@testable import HubDesign

/// Réglages › Colin (18/11): after how many days the Accueil signals a mail left without an answer, and a client who
/// no longer answers.
@Suite struct ColinPreferencesTests {
    func defaults() -> UserDefaults {
        let name = "colin-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theKeysAreThoseOfTheBrief() {
        #expect(Preferences.Key.colinReplyDays == "colin.reponseAttendue.jours")
        #expect(Preferences.Key.colinSilentDays == "colin.clientMuet.jours")
    }

    @Test func theThresholdsDefaultToThreeAndSevenDays() {
        let settings = Preferences(defaults: defaults())
        #expect(settings.colinReplyDays == 3)
        #expect(settings.colinSilentDays == 7)
        #expect(Preferences.Default.colinReplyDays == 3 && Preferences.Default.colinSilentDays == 7)
        #expect(Preferences.Default.colinReplyChoices == [2, 3, 5, 7])
        #expect(Preferences.Default.colinSilentChoices == [5, 7, 10, 14])
    }

    @Test func aChosenValueIsRead() {
        let defaults = defaults()
        let settings = Preferences(defaults: defaults)
        defaults.set(5, forKey: Preferences.Key.colinReplyDays)
        defaults.set(14, forKey: Preferences.Key.colinSilentDays)
        #expect(settings.colinReplyDays == 5)
        #expect(settings.colinSilentDays == 14)
    }

    /// A value nobody could have chosen (an older version's, a hand in the defaults) never makes the Accueil signal
    /// everything, or nothing.
    @Test func aValueOutOfTheChoicesFallsBack() {
        let defaults = defaults()
        let settings = Preferences(defaults: defaults)
        defaults.set(4, forKey: Preferences.Key.colinReplyDays)
        defaults.set(0, forKey: Preferences.Key.colinSilentDays)
        #expect(settings.colinReplyDays == 3)
        #expect(settings.colinSilentDays == 7)
        defaults.set(-2, forKey: Preferences.Key.colinReplyDays)
        defaults.set(10_000, forKey: Preferences.Key.colinSilentDays)
        #expect(settings.colinReplyDays == 3)
        #expect(settings.colinSilentDays == 7)
        defaults.set("bientôt", forKey: Preferences.Key.colinReplyDays)
        defaults.set(Date(), forKey: Preferences.Key.colinSilentDays)
        #expect(settings.colinReplyDays == 3)
        #expect(settings.colinSilentDays == 7)
    }

    @Test func colinIsOffByDefault() throws {
        let suite = "colin-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Preferences.Key.colinOn == "colin.enMarche")
        #expect(!Preferences(defaults: defaults).colinOn)
        // Step 3 (18/11): Colin does not keep the kanban by himself until Paul says so.
        #expect(Preferences.Key.colinKanban == "colin.tableauSeul")
        #expect(!Preferences(defaults: defaults).colinKanban)
        defaults.set(true, forKey: Preferences.Key.colinOn)
        #expect(Preferences(defaults: defaults).colinOn)
        defaults.set("oui", forKey: Preferences.Key.colinOn)
        #expect(!Preferences(defaults: defaults).colinOn)
    }
}
