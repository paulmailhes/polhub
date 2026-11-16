import Foundation
import Testing
@testable import PolhubDesign

/// Réglages › Inspiration (16/11): the collection and the AI's categories are on until Paul turns them off; the
/// old copy's folder is chosen by him, never written in the code.
@Suite struct InspirationPreferencesTests {
    func defaults() -> UserDefaults {
        let name = "inspiration-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theKeysAreThoseOfTheBrief() {
        #expect(Preferences.Key.inspirationAutoCollect == "inspiration.collecteAuto")
        #expect(Preferences.Key.inspirationAICategories == "inspiration.categoriesIA")
        #expect(Preferences.Key.inspirationOldCopyFolder == "inspiration.dossierAncienneCopie")
    }

    @Test func collectionAndCategoriesAreOnByDefault() {
        let defaults = defaults()
        let settings = Preferences(defaults: defaults)
        #expect(settings.inspirationAutoCollect && settings.inspirationAICategories)
        #expect(settings.inspirationOldCopyFolder == nil)
        defaults.set(false, forKey: Preferences.Key.inspirationAutoCollect)
        defaults.set(false, forKey: Preferences.Key.inspirationAICategories)
        defaults.set("/tmp/ancienne-copie", forKey: Preferences.Key.inspirationOldCopyFolder)
        #expect(!settings.inspirationAutoCollect && !settings.inspirationAICategories)
        #expect(settings.inspirationOldCopyFolder == "/tmp/ancienne-copie")
        // An emptied folder is no folder.
        defaults.set("", forKey: Preferences.Key.inspirationOldCopyFolder)
        #expect(settings.inspirationOldCopyFolder == nil)
    }
}
