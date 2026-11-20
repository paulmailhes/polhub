import Foundation
import Testing
@testable import HubDesign

/// Réglages › Inspiration (16/11): the collection and the AI's categories are on until Paul turns them off.
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
    }

    @Test func collectionAndCategoriesAreOnByDefault() {
        let defaults = defaults()
        let settings = Preferences(defaults: defaults)
        #expect(settings.inspirationAutoCollect && settings.inspirationAICategories)
        defaults.set(false, forKey: Preferences.Key.inspirationAutoCollect)
        defaults.set(false, forKey: Preferences.Key.inspirationAICategories)
        #expect(!settings.inspirationAutoCollect && !settings.inspirationAICategories)
    }
}
