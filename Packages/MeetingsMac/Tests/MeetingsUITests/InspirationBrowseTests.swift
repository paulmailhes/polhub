import Foundation
import Persistence
import PolhubDesign
import Testing
@testable import MeetingsUI

/// The pages of « Inspiration » without a screen (16/11): the search, the filters (one value per family), the chips
/// each family offers, a card's line, an item's links and categories.
@MainActor @Suite struct InspirationBrowseTests {
    static let now = InspirationTestWorld.day(11, 16)

    static func site(_ title: String, url: String = "https://www.exemple.fr/", categories: [String: [String]] = [:],
                     text: String = "", fonts: [String] = [], date: Date = now) -> InspirationItemRow {
        InspirationItemRow(kind: .website, key: url, title: title, text: text, url: url, date: date, categories: categories, fonts: fonts, createdAt: date)
    }

    static func post(_ title: String, sources: [String], studio: String? = nil, categories: [String: [String]] = [:]) -> InspirationItemRow {
        InspirationItemRow(kind: .branding, key: UUID().uuidString, title: title, date: now, sources: sources, studio: studio,
                           categories: categories, createdAt: now)
    }

    @Test func thePagesKeepTheVaultsNames() {
        #expect(InspirationKind.allCases.map(\.title) == ["Websites", "Branding", "Mock-ups"])
        #expect(InspirationKind.allCases.map(\.addTitle) == ["Ajouter un site", "Ajouter une page LinkedIn", "Ajouter un mock-up"])
        #expect(InspirationKind.website.count(1) == "1 site" && InspirationKind.website.count(212) == "212 sites")
        #expect(InspirationKind.branding.count(488) == "488 branding" && InspirationKind.mockup.count(292) == "292 mock-ups")
        #expect(Set(InspirationKind.allCases.map(\.appIcon)).count == 3)
    }

    /// Every word somewhere in the item, accents and case aside: title, text, fonts, the site's host, categories.
    @Test func theSearchFindsEveryWordAnywhereWithoutAccents() {
        let items = [
            Self.site("Maison Lumière", url: "https://maison-lumiere.exemple.fr", categories: ["style": ["éditorial"]], fonts: ["Exemple Serif"]),
            Self.site("Atelier Nord", url: "https://atelier-nord.example.com", text: "Un studio de céramique."),
        ]
        func titles(_ query: String) -> [String] { InspirationBrowse.filter(items, query: query, filters: [:]).map(\.title) }
        #expect(titles("") == ["Maison Lumière", "Atelier Nord"])
        #expect(titles("lumiere") == ["Maison Lumière"])
        #expect(titles("EDITORIAL serif") == ["Maison Lumière"])
        #expect(titles("ceramique") == ["Atelier Nord"])
        #expect(titles("atelier-nord.example") == ["Atelier Nord"])
        #expect(titles("lumière nord").isEmpty)
    }

    /// One value per family; an item shows when it has every value chosen; the pages filter Branding as a family.
    @Test func theFiltersKeepTheItemsWithEveryValueChosen() {
        let items = [
            Self.post("Café Nord", sources: ["Studio Exemple"], categories: ["secteur": ["restaurant"], "style": ["rétro"]]),
            Self.post("Fondation", sources: ["Atelier Nord", "Studio Exemple"], categories: ["secteur": ["culture"], "style": ["rétro"]]),
            Self.post("Marque", sources: ["Galerie Exemple"], categories: ["secteur": ["mode"]]),
        ]
        func titles(_ filters: [String: String]) -> [String] { InspirationBrowse.filter(items, query: "", filters: filters).map(\.title) }
        #expect(titles(["style": "rétro"]) == ["Café Nord", "Fondation"])
        #expect(titles(["style": "RETRO"]) == ["Café Nord", "Fondation"])
        #expect(titles(["style": "rétro", "secteur": "culture"]) == ["Fondation"])
        #expect(titles(["source": "Studio Exemple"]) == ["Café Nord", "Fondation"])
        #expect(titles(["source": "Galerie Exemple", "style": "rétro"]).isEmpty)
        #expect(titles(["style": ""]).count == 3)
    }

    /// The chips of a family are the values the items have, given the search and the other families' choices, the
    /// most used first; the value chosen stays; Branding's pages come first, in their colors.
    @Test func eachFamilyOffersTheValuesThatLeadSomewhere() throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let library = world.library()
        let vocabulary = library.vocabulary(.branding)
        let items = [
            Self.post("Café Nord", sources: ["Studio Exemple"], categories: ["secteur": ["restaurant"], "style": ["rétro"]]),
            Self.post("Brasserie", sources: ["Studio Exemple"], categories: ["secteur": ["boisson"], "style": ["rétro", "chaleureux"]]),
            Self.post("Fondation", sources: ["Atelier Nord"], categories: ["secteur": ["culture"], "style": ["typographique"], "autres": ["Vintage"]]),
        ]
        let sources = [InspirationSourceRow(name: "Studio Exemple", link: "https://www.linkedin.com/company/studio-exemple/", color: "#E8B923", createdAt: Self.now)]
        let rows = InspirationBrowse.chipRows(items, kind: .branding, vocabulary: vocabulary, sources: sources, query: "", filters: [:])
        #expect(rows.map(\.family) == ["source", "secteur", "style", "autres"])
        #expect(rows.map(\.title) == ["Source", "Secteur", "Style", "Autres"])
        let style = try #require(rows.first { $0.family == "style" })
        // Two items for « rétro »; then the vocabulary's order, where « typographique » comes before « chaleureux ».
        #expect(style.values.map(\.value) == ["rétro", "typographique", "chaleureux"])
        #expect(style.values.first?.count == 2 && style.values.first?.label == "Rétro")
        let source = try #require(rows.first)
        #expect(source.values.map(\.value) == ["Studio Exemple", "Atelier Nord"])
        #expect(source.values.first?.color == "#E8B923")
        #expect(source.values.last?.color == InspirationBrowse.derivedColor("Atelier Nord"))

        // Choosing « Atelier Nord » narrows the other families, never its own.
        let narrowed = InspirationBrowse.chipRows(items, kind: .branding, vocabulary: vocabulary, sources: sources, query: "",
                                                  filters: ["source": "Atelier Nord"])
        #expect(narrowed.first { $0.family == "style" }?.values.map(\.value) == ["typographique"])
        #expect(narrowed.first?.values.count == 2 && narrowed.first?.selected == "Atelier Nord")
        // A value chosen that the search leaves out still shows, to be unchosen.
        let searched = InspirationBrowse.chipRows(items, kind: .branding, vocabulary: vocabulary, sources: sources, query: "brasserie",
                                                  filters: ["secteur": "culture"])
        let secteur = try #require(searched.first { $0.family == "secteur" })
        #expect(secteur.selected == "culture" && secteur.values.contains { $0.value == "culture" && $0.count == 0 })
        #expect(searched.first { $0.family == "autres" } == nil)
    }

    @Test func mockupsFilterByType() throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let vocabulary = world.library().vocabulary(.mockup)
        let items = [InspirationItemRow(kind: .mockup, key: "Affiche", title: "Affiche", date: Self.now, categories: ["type": ["affiche", "signaletique"]], createdAt: Self.now)]
        let rows = InspirationBrowse.chipRows(items, kind: .mockup, vocabulary: vocabulary, sources: [], query: "", filters: [:])
        #expect(rows.map(\.title) == ["Type"])
        #expect(Set(rows[0].values.map(\.value)) == ["affiche", "signaletique"])
    }

    /// Websites: the date and the host; Branding: the date and the studio (or the page); Mock-ups: the types.
    @Test func aCardSaysWhenAndWhoInOneLine() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let site = Self.site("Maison", url: "https://www.maison-lumiere.exemple.fr/fr/", date: InspirationTestWorld.day(10, 20))
        #expect(InspirationBrowse.meta(site, now: Self.now, calendar: calendar) == "20 oct. · maison-lumiere.exemple.fr")
        let old = Self.site("Ancien", url: "https://ancien.exemple.fr", date: InspirationTestWorld.day(3, 2, year: 2025))
        #expect(InspirationBrowse.meta(old, now: Self.now, calendar: calendar) == "2 mars 2025 · ancien.exemple.fr")
        #expect(InspirationBrowse.meta(Self.post("Café", sources: ["Studio Exemple"], studio: "Atelier Nord"), now: Self.now, calendar: calendar)
                == "16 nov. · Atelier Nord")
        #expect(InspirationBrowse.meta(Self.post("Café", sources: ["Studio Exemple"]), now: Self.now, calendar: calendar) == "16 nov. · Studio Exemple")
        let mockup = InspirationItemRow(kind: .mockup, key: "A", title: "A", date: Self.now, categories: ["type": ["affiche", "signaletique"]], createdAt: Self.now)
        #expect(InspirationBrowse.meta(mockup, now: Self.now, calendar: calendar) == "Affiche, signalétique")
    }

    /// The vault writes the mock-ups' types without accents: the chips give them back.
    @Test func theTypesGetTheirAccentsBack() {
        #expect(["signaletique", "boite aux lettres", "iphone", "tote bag", "ecran"].map(InspirationBrowse.label)
                == ["Signalétique", "Boîte aux lettres", "iPhone", "Tote bag", "Écran"])
    }

    /// The vocabulary's words read as words on the chips: « 3D », « GSAP », « Bas de casse », « Police sur mesure »;
    /// a hyphen that belongs to the word stays (« E-commerce », « Non-lucratif ») (review of 16/11).
    @Test func theChipsReadAsWords() {
        #expect(["3d", "gsap", "bas-de-casse", "police-sur-mesure", "sombre-clair"].map(InspirationBrowse.label)
                == ["3D", "GSAP", "Bas de casse", "Police sur mesure", "Sombre / clair"])
        #expect(["e-commerce", "non-lucratif", "minimal", "webflow"].map(InspirationBrowse.label) == ["E-commerce", "Non-lucratif", "Minimal", "Webflow"])
    }

    /// A long row shows its most used values, then « +N » for the others, in a menu: every value is one click
    /// away, with a mouse wheel too (review of 16/11: the chips past the edge could only be reached with a
    /// trackpad); the value chosen always shows.
    @Test func aLongRowKeepsTheRestInAMenu() {
        let values = (1...20).map { InspirationBrowse.ChipValue(value: "v\($0)", count: 21 - $0, color: nil) }
        let row = InspirationBrowse.ChipRow(family: "style", title: "Style", values: values, selected: "V18")
        let split = InspirationBrowse.visibleChips(row, limit: 8)
        #expect(split.shown.map(\.value) == (1...8).map { "v\($0)" } + ["v18"])
        #expect(split.more.map(\.value) == ((9...17).map { "v\($0)" } + ["v19", "v20"]))
        let short = InspirationBrowse.ChipRow(family: "style", title: "Style", values: Array(values.prefix(9)), selected: nil)
        #expect(InspirationBrowse.visibleChips(short, limit: 8).shown.count == 9 && InspirationBrowse.visibleChips(short, limit: 8).more.isEmpty)
    }

    /// The window's subtitle: the count, « N sur M » while filtered, nothing on an empty page.
    @Test func theSubtitleCountsWhatIsShown() {
        #expect(InspirationBrowse.subtitle(.website, shown: 212, total: 212) == "212 sites")
        #expect(InspirationBrowse.subtitle(.website, shown: 4, total: 212) == "4 sites sur 212")
        #expect(InspirationBrowse.subtitle(.branding, shown: 0, total: 10) == "0 branding sur 10")
        #expect(InspirationBrowse.subtitle(.mockup, shown: 0, total: 0).isEmpty)
    }

    /// A page without a color gets one from its name, the same on every launch.
    @Test func aPageWithoutColorGetsOneFromItsName() {
        let first = InspirationBrowse.derivedColor("Galerie Exemple")
        #expect(first == InspirationBrowse.derivedColor("galerie exemple"))
        #expect(InspirationBrowse.isHex(first))
        let sources = [InspirationSourceRow(name: "Galerie Exemple", link: "https://www.linkedin.com/company/galerie-exemple/", color: "pas une couleur", createdAt: Self.now)]
        #expect(InspirationBrowse.color(ofSource: "Galerie Exemple", in: sources) == first)
    }

    /// The links: the site, the post, the mock-up's folder in the Finder when it is on the Mac, else its link.
    @Test func anItemOpensWhereItLives() throws {
        #expect(InspirationBrowse.links(Self.site("Maison", url: "https://maison.exemple.fr")).map(\.title) == ["Ouvrir le site"])
        var post = Self.post("Café", sources: ["Studio Exemple"])
        post.url = "https://www.linkedin.com/feed/update/urn:li:activity:7390000000000000000/"
        post.links = [post.url!, "https://cafe-nord.exemple.fr", "https://cafe-nord.exemple.fr", "mailto:bonjour@exemple.fr"]
        #expect(InspirationBrowse.links(post).map(\.title) == ["Voir sur LinkedIn"])
        #expect(InspirationBrowse.otherLinks(post).map(\.absoluteString) == ["https://cafe-nord.exemple.fr"])
        var mockup = InspirationItemRow(kind: .mockup, key: "Affiche", title: "Affiche", date: Self.now,
                                        extra: InspirationExtra(folderURL: "https://cloud.example.com/apps/files/?dir=/Mock-ups/Affiche"), createdAt: Self.now)
        #expect(InspirationBrowse.links(mockup, folderExists: { _ in true }) == [
            InspirationBrowse.Link(title: "Ouvrir le dossier", target: .web(try #require(URL(string: "https://cloud.example.com/apps/files/?dir=/Mock-ups/Affiche")))),
        ])
        mockup.extra.localFolder = "/Volumes/Exemple/Mock-ups/Affiche"
        #expect(InspirationBrowse.links(mockup, folderExists: { _ in true }).first?.isFinder == true)
        #expect(InspirationBrowse.links(mockup, folderExists: { _ in false }).first?.isFinder == false)
        #expect(InspirationBrowse.links(Self.site("Sans adresse", url: "javascript:alert(1)")).isEmpty)
    }

    /// A click ticks or unticks a value; a family left empty goes; the vocabulary's families all show, the unknown ones after.
    @Test func categoriesChangeWithAClick() throws {
        let world = try InspirationTestWorld()
        defer { world.clean() }
        let vocabulary = world.library().vocabulary(.website)
        var categories = ["style": ["minimal"]]
        categories = InspirationBrowse.toggling(categories, family: "style", value: "luxe")
        #expect(categories == ["style": ["minimal", "luxe"]])
        categories = InspirationBrowse.toggling(categories, family: "style", value: "MINIMAL")
        categories = InspirationBrowse.toggling(categories, family: "style", value: "luxe")
        #expect(categories.isEmpty)
        let item = Self.site("Maison", categories: ["style": ["minimal"], "autres": ["Vintage"]])
        let rows = InspirationBrowse.categoryRows(item, vocabulary: vocabulary)
        #expect(rows.map(\.family) == ["secteur", "style", "techno", "typo", "support", "autres"])
        #expect(rows[1].values == ["minimal"] && rows[1].options.contains("brutaliste"))
        #expect(rows.last?.options == ["Vintage"] && rows.last?.title == "Autres")
    }

    /// An address as typed: the scheme added, a host required.
    @Test func anAddressReadsAsTyped() {
        #expect(InspirationLibrary.siteURL("exemple.fr")?.absoluteString == "https://exemple.fr")
        #expect(InspirationLibrary.siteURL(" https://www.exemple.fr/projets ")?.absoluteString == "https://www.exemple.fr/projets")
        #expect(InspirationLibrary.siteURL("pas une adresse") == nil)
        #expect(InspirationLibrary.siteURL("localhost") == nil)
        #expect(InspirationLibrary.siteURL("ftp://exemple.fr") == nil)
    }

    /// Réglages › Inspiration in plain words: when a page was read, what went wrong.
    @Test func theCollectionSaysHowItWentInPlainWords() {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let now = Self.now
        let read = now.addingTimeInterval(-3_600)
        let source = InspirationSourceRow(name: "Studio Exemple", link: "https://www.linkedin.com/company/studio-exemple/", lastReadAt: read, createdAt: now)
        let line = InspirationSettingsText.sourceLine(source, status: nil, now: now)
        #expect(line.text.hasPrefix("linkedin.com/company/studio-exemple · lue aujourd'hui à ") && !line.problem)
        let refused = InspirationSettingsText.sourceLine(source, status: InspirationStatusLine(id: source.link, name: "Studio Exemple", lastRun: now,
                                                                                                problem: "LinkedIn demande une connexion"), now: now)
        #expect(refused.problem && refused.text.hasPrefix("LinkedIn demande une connexion (aujourd'hui à "))
        let awwwards = InspirationSettingsText.statusLine(InspirationStatusLine(id: "awwwards", name: "Awwwards", lastRun: read, added: 1), now: now)
        #expect(awwwards.text.hasPrefix("Awwwards : lu aujourd'hui à ") && awwwards.text.hasSuffix(", 1 nouveau site"))
        // Says what was added, as the collection words it (review of 16/11: « 1 ajouté », 1 what?).
        func awwwardsLine(_ added: Int?) -> String {
            InspirationSettingsText.statusLine(InspirationStatusLine(id: "awwwards", name: "Awwwards", lastRun: read, added: added), now: now).text
        }
        #expect(awwwardsLine(3).hasSuffix(", 3 nouveaux sites") && awwwardsLine(0).hasSuffix(", rien de nouveau"))
        #expect(awwwardsLine(nil).hasPrefix("Awwwards : lu aujourd'hui à ") && !awwwardsLine(nil).contains(","))
        func pageLine(_ added: Int?) -> String {
            InspirationSettingsText.sourceLine(source, status: InspirationStatusLine(id: source.link, name: "Studio Exemple", lastRun: now, added: added),
                                               now: now).text
        }
        #expect(pageLine(2).hasPrefix("linkedin.com/company/studio-exemple · lue aujourd'hui à ") && pageLine(2).hasSuffix(", 2 nouveaux posts"))
        #expect(pageLine(1).hasSuffix(", 1 nouveau post") && pageLine(0).hasSuffix(", aucun nouveau post"))
        // A reading restored from the base: its count is not known, nothing is said of it.
        #expect(!line.text.contains("post") && !pageLine(nil).contains("post"))
        #expect(InspirationSettingsText.statusLine(InspirationStatusLine(id: "awwwards", name: "Awwwards"), now: now).text == "Awwwards : pas encore lu")
        #expect(InspirationSettingsText.when(now.addingTimeInterval(-86_400), now: now).hasPrefix("hier à "))
    }
}
