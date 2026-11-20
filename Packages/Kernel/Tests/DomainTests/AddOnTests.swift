import Domain
import Foundation
import Testing

/// 20/11 : hub est un socle et des add-ons. Une base existante les a tous (rien ne disparaît chez Paul), une base neuve
/// aucun ; un add-on vient avec ceux dont il a besoin, et part avec ceux qui ont besoin de lui.
@Suite struct AddOnTests {
    func store() throws -> AddOnStore {
        AddOnStore(defaults: try #require(UserDefaults(suiteName: "addons-\(UUID().uuidString)")))
    }

    @Test func anExistingBaseHasEveryAddOn() throws {
        let store = try store()
        store.settle(baseExists: true)
        #expect(store.installed == Set(AddOn.allCases))
    }

    @Test func aNewBaseHasNone() throws {
        let store = try store()
        store.settle(baseExists: false)
        #expect(store.installed.isEmpty)
    }

    @Test func settlingTwiceKeepsWhatWasChosen() throws {
        let store = try store()
        store.settle(baseExists: false)
        store.save([.projects])
        store.settle(baseExists: true)
        #expect(store.installed == [.projects])
    }

    @Test func withoutTheKeyEverythingIsInstalled() throws {
        #expect(try store().installed == Set(AddOn.allCases))
    }

    @Test func installingColinBringsMailsAndCalendar() {
        #expect(AddOns.installing(.colin, into: []) == [.colin, .mails, .calendar])
        #expect(AddOns.added(by: .colin, to: []) == [.calendar, .mails])
        #expect(AddOns.added(by: .colin, to: [.calendar]) == [.mails])
        #expect(AddOns.added(by: .projects, to: []).isEmpty)
    }

    @Test func uninstallingCalendarTakesMailsAndColin() {
        let all = Set(AddOn.allCases)
        let left = AddOns.uninstalling(.calendar, from: all)
        #expect(!left.contains(.calendar) && !left.contains(.mails) && !left.contains(.colin))
        #expect(left.contains(.projects) && left.contains(.meetings))
        #expect(AddOns.removed(by: .calendar, from: all) == [.mails, .colin])
        #expect(AddOns.removed(by: .projects, from: all).isEmpty)
    }

    @Test func theIdentifiersAndNamesAreFixed() {
        #expect(AddOn.allCases.map(\.rawValue) == ["projets", "reunions", "calendrier", "mails", "inspiration", "colin", "iphone"])
        #expect(AddOn.allCases.map(\.title) == ["Projets", "Réunions", "Calendrier", "Mails", "Inspiration", "Colin", "iPhone"])
        #expect(AddOnStore.key == "addOns.installes")
    }
}
