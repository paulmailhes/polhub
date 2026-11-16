import Foundation
import Persistence
import Testing
@testable import Inspiration

/// The vault's import (16/11): Websites, Branding (and its `_sources.md`), Mock-ups, from the vault and an
/// optional old copy, read-only, merged by key, run as often as Paul likes.
@Suite(.serialized) struct InspirationImportTests {
    func localDay(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func theExampleVaultIsImportedWhole() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let report = try await example.run()
        #expect(report[.website].added == 7 && report[.website].duplicates == 1 && report[.website].skipped == 3)
        #expect(report[.branding].added == 4 && report[.branding].duplicates == 1 && report[.branding].skipped == 0)
        #expect(report[.mockup].added == 3 && report[.mockup].skipped == 0)
        #expect(report.sourcesAdded == 3)
        #expect(try example.store.items(kind: .website).count == 7)
        #expect(try example.store.items(kind: .branding).count == 4)
        #expect(try example.store.items(kind: .mockup).count == 3)
        // Studio Exemple, Atelier Nord; Café Nord ×3, Fondation, Marque ×5; two previews.
        #expect(report.imagesConverted == 13 && report.imagesReused == 0 && report.imagesLeftOut == 1)
        #expect(report.bytesWritten > 0 && report.imageBytes == report.bytesWritten)
        #expect(report.summary.hasPrefix("7 sites, 4 branding, 3 mock-ups ; "))
        // Each skipped note says why, by its title only.
        #expect(report.warnings.contains { $0.hasPrefix("« Sans adresse » :") })
        #expect(report.warnings.contains { $0.hasPrefix("« YAML cassé » :") })
        #expect(report.warnings.contains { $0.hasPrefix("« Brouillon » :") })
        #expect(!report.warnings.contains { $0.contains("_Galerie") })
    }

    /// A site's key is its address, written one way: `www.`, `http`, the slash at the end do not make two sites;
    /// two notes called « Home » for two sites stay two.
    @Test func aSiteIsKeyedByItsAddress() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let site = try #require(try example.store.item(kind: .website, key: "https://studio-exemple.fr"))
        #expect(site.title == "Studio Exemple — Design graphique")
        #expect(site.url == "https://www.studio-exemple.fr/")
        #expect(site.text == "Studio Exemple, design graphique et identités pour la culture.")
        #expect(site.date == localDay(2026, 11, 2))
        // `portfolio` is in secteur and in support: in both, as the vault's tag bar showed it (review of 16/11).
        #expect(site.categories == ["secteur": ["agence", "portfolio"], "style": ["minimal", "typographique"], "support": ["portfolio"]])
        #expect(!site.categoriesByPaul && site.client == "studio de design graphique" && site.fonts.isEmpty)
        #expect(site.images == [InspirationImageName.website(key: "https://studio-exemple.fr")])
        let probe = try #require(TestImages.Probe(example.imageURL(.website, site.images[0])))
        #expect(probe.width == 1600 && probe.height == 840)
        let homes = try example.store.items(kind: .website).filter { $0.title.hasPrefix("Home") }.map(\.key).sorted()
        #expect(homes == ["https://example.com/portfolio", "https://exemple.fr"])
    }

    @Test func theAddressIsNormalised() {
        #expect(InspirationKeys.website("https://www.Studio-Exemple.fr/") == "https://studio-exemple.fr")
        #expect(InspirationKeys.website("http://studio-exemple.fr") == "https://studio-exemple.fr")
        #expect(InspirationKeys.website("https://exemple.fr/Projets/Alpha/?ref=awwwards#haut") == "https://exemple.fr/Projets/Alpha")
        #expect(InspirationKeys.website("exemple.fr/portfolio") == "https://exemple.fr/portfolio")
        #expect(InspirationKeys.website("https://exemple.fr:8443/") == "https://exemple.fr:8443")
        #expect(InspirationKeys.website("pas une adresse") == nil)
        #expect(InspirationKeys.website("mailto:contact@exemple.fr") == nil)
    }

    /// A note Paul tagged by hand (`ia_manuel`) keeps his categories, fonts and client as his.
    @Test func paulsHandTagsStayHis() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let atelier = try #require(try example.item(.website, titled: "Atelier Nord"))
        #expect(atelier.categoriesByPaul)
        #expect(atelier.categories == ["secteur": ["culture"], "style": ["éditorial"], "support": ["éditorial"], "autres": ["fait-main"]])
        #expect(atelier.fonts == ["Garamond Exemple"] && atelier.client == "studio d'architecture intérieure")
        #expect(atelier.extra.notion == "0123456789abcdef0123456789abcdef" && atelier.extra.projects == ["Site vitrine"])
        #expect(atelier.date == localDay(2025, 3, 14))
        #expect(atelier.importedFrom == "database/Websites/Atelier Nord.md")
        let fondation = try #require(try example.item(.branding, titled: "Fondation Exemple"))
        #expect(fondation.categoriesByPaul)
        #expect(fondation.categories == ["secteur": ["culture"], "style": ["typographique"], "support": ["affiche"]])
        #expect(TestImages.Probe(example.imageURL(.branding, fondation.images[0]))?.width == 1600)
    }

    /// An image only known by its address is kept as an address; a missing one, or a page saved as an image, is
    /// said in one line, by the note's title, and the note is kept without it.
    @Test func imagesThatCannotComeAreSaidSo() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let report = try await example.run()
        let galerie = try #require(try example.item(.website, titled: "Galerie Lumière"))
        #expect(galerie.images.isEmpty && galerie.extra.imageURL == "https://galerie-lumiere.example.com/og.jpg")
        // Said too: the collection downloads it afterwards (review of 16/11).
        #expect(report.warnings.contains { $0.hasPrefix("« Galerie Lumière » :") && $0.contains("image en ligne") })
        let maison = try #require(try example.item(.website, titled: "Maison Exemple"))
        #expect(maison.images.isEmpty)
        #expect(report.warnings.contains { $0.hasPrefix("« Maison Exemple » :") && $0.contains("introuvable") })
        let page = try #require(try example.item(.website, titled: "Page enregistrée en HTML"))
        #expect(page.images.isEmpty)
        #expect(report.warnings.contains { $0.hasPrefix("« Page enregistrée en HTML » :") && $0.contains("ce n'est pas une image lisible") })
        // Nothing of a note's content beyond its title.
        #expect(!report.warnings.contains { $0.contains("Mobilier") || $0.contains("galerie de photographie") })
        #expect(report.warnings.allSatisfy { !$0.contains("\n") })
    }

    /// A post's still images, its cover first (the first frame of a GIF), its text without the embeds nor the
    /// LinkedIn link, its date from its id.
    @Test func aBrandingPostKeepsItsStillImages() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let cafe = try #require(try example.store.item(kind: .branding, key: "7479089115955373553"))
        #expect(cafe.title == "Café Nord" && cafe.studio == "Atelier Nord")
        #expect(cafe.date == Date(timeIntervalSince1970: 1_783_153_800))
        #expect(cafe.url == "https://www.linkedin.com/feed/update/urn:li:activity:7479089115955373553/")
        #expect(cafe.images == (1...3).map { InspirationImageName.branding(urn: "7479089115955373553", index: $0) })
        // The cover is the vault's (the JPEG), then the GIF's first frame, then the PNG.
        let cover = try #require(TestImages.Probe(example.imageURL(.branding, cafe.images[0])))
        #expect(cover.width == 1080 && cover.height == 1350 && cover.type == "public.jpeg")
        let frame = try #require(TestImages.Probe(example.imageURL(.branding, cafe.images[1])))
        #expect(frame.width == 800 && frame.pixel(x: 5, y: 5).red > 200)
        #expect(cafe.text.hasPrefix("Café Nord by Atelier Nord\nUne identité chaleureuse"))
        #expect(!cafe.text.contains("![[") && !cafe.text.contains("Voir sur LinkedIn"))
        #expect(cafe.links == ["https://atelier-nord.example.com/cafe-nord"])
        #expect(cafe.categories == ["secteur": ["restaurant"], "style": ["chaleureux", "artisanal"], "support": ["logo", "packaging"]])
        #expect(cafe.fonts == ["Garamond Exemple"] && cafe.client == "café de quartier")
        #expect(cafe.extra.hiddenImages == 2)
        #expect(cafe.importedFrom == "database/Branding/2026-07-04 Café Nord.md")
    }

    /// The same project posted by two pages: one item, the one with the most images, both pages on it, and the
    /// other id kept so that a collection never brings it back.
    @Test func theSameProjectFromTwoPagesIsOneItem() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let cafes = try example.store.items(kind: .branding).filter { $0.title == "Café Nord" }
        #expect(cafes.count == 1)
        let cafe = try #require(cafes.first)
        #expect(cafe.key == "7479089115955373553" && cafe.images.count == 3)
        #expect(cafe.sources == ["Galerie Exemple", "Revue Exemple"])
        #expect(cafe.extra.aliases == ["7481000460288173553"])
        #expect(cafe.extra.hashtags == ["branding", "cafe", "identite"])
        #expect(try example.store.knownKeys(kind: .branding).isSuperset(of: ["7479089115955373553", "7481000460288173553"]))
    }

    @Test func aPostKeepsAtMostFiveImages() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let report = try await example.run()
        let marque = try #require(try example.item(.branding, titled: "Marque Exemple"))
        #expect(marque.images.count == 5 && report.imagesLeftOut == 1)
        #expect(marque.links == ["https://studio-exemple.fr/marque", "https://www.linkedin.com/company/studio-exemple"])
        #expect(marque.extra.hashtags == ["rebrand"])
        // More if asked.
        let again = try ExampleVault()
        defer { again.remove() }
        _ = try await again.run(options: .init(maxBrandingImages: 10))
        #expect(try again.item(.branding, titled: "Marque Exemple")?.images.count == 6)
    }

    /// An id larger than 2^53 stays exact, quoted or not; a post without image keeps its words only.
    @Test func anUnquotedIdStaysExact() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let post = try #require(try example.item(.branding, titled: "Publication sans image"))
        #expect(post.key == "7500458675404973553")
        #expect(post.date == Date(timeIntervalSince1970: 1_788_248_700))
        #expect(post.images.isEmpty && post.studio == nil)
        #expect(post.text == "Une publication sans image, seulement une vidéo.")
        #expect(post.sources == ["Galerie Exemple"])
    }

    /// The LinkedIn pages come from `_sources.md`, each once; a page Paul changed in Polhub stays as he left it.
    @Test func theLinkedInPagesComeFromTheSourcesTable() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let pages = try example.store.sources()
        #expect(pages.map(\.name) == ["Atelier Exemple", "Galerie Exemple", "Revue Exemple"])
        #expect(pages.map(\.link) == ["https://www.linkedin.com/company/atelier-exemple/", "https://www.linkedin.com/company/galerie-exemple/",
                                      "https://www.linkedin.com/company/revue-exemple/"])
        #expect(pages.map(\.color) == [nil, "#e8b923", "#2f6fed"])
        var galerie = pages[1]
        galerie.color = "#123456"
        try example.store.saveSource(galerie)
        let report = try await example.run()
        #expect(report.sourcesAdded == 0)
        #expect(try example.store.sources().count == 3 && example.store.sources()[1].color == "#123456")
    }

    @Test func theSourcesTableIsRead() {
        let table = """
            | Nom | Lien | Couleur |
            | --- | --- | --- |
            | Galerie Exemple | https://fr.linkedin.com/company/Galerie-Exemple/posts/ | #E8B923 |
            | Sans lien | pas un lien | #000000 |
            | Couleur fausse | https://www.linkedin.com/company/couleur-fausse/ | rouge |
            """
        let pages = SourcesTable.parse(table)
        #expect(pages.map(\.name) == ["Galerie Exemple", "Couleur fausse"])
        #expect(pages.map(\.link) == ["https://www.linkedin.com/company/galerie-exemple/", "https://www.linkedin.com/company/couleur-fausse/"])
        #expect(pages.map(\.color) == ["#e8b923", nil])
    }

    /// A mock-up: its preview, its folder in Nextcloud as key, its types under `type`.
    @Test func aMockupKeepsItsPreviewAndLinks() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let affiche = try #require(try example.store.item(kind: .mockup, key: "Affiche urbaine"))
        #expect(affiche.title == "Affiche urbaine" && affiche.studio == "Studio Exemple Mockups")
        #expect(affiche.categories == ["type": ["affiche", "signaletique"]])
        #expect(affiche.extra.folderURL == "https://cloud.exemple.fr/apps/files/?dir=/Ressources/Mock-ups/Affiche%20urbaine")
        #expect(affiche.extra.fileURL?.hasSuffix("/affiche.psd") == true && affiche.extra.previewURL?.hasSuffix("/apercu.jpg") == true)
        #expect(affiche.extra.sizeMB == 245.3)
        #expect(affiche.date == localDay(2025, 1, 12))
        #expect(affiche.images == [InspirationImageName.mockup(folder: "Affiche urbaine")])
        #expect(TestImages.Probe(example.imageURL(.mockup, affiche.images[0]))?.width == 900)
        let carte = try #require(try example.store.item(kind: .mockup, key: "Carte de visite"))
        // The tags that repeat `type` and `source` are not categories.
        #expect(carte.categories == ["type": ["business card"]] && carte.images.isEmpty && carte.extra.sizeMB == 80)
        let boite = try #require(try example.store.item(kind: .mockup, key: "Boîte carton"))
        #expect(boite.title == "Boîte" && boite.text == "Une boîte en carton, trois vues.")
        #expect(boite.categories == ["type": ["boite", "divers"], "autres": ["a-revoir"]])
        #expect(boite.images.count == 1)
    }

    @Test func theFolderOfAMockupIsReadFromItsLinks() {
        #expect(InspirationKeys.mockupFolder(folderLink: "https://cloud.exemple.fr/apps/files/?dir=/Ressources/Mock-ups/Bo%C3%AEte%20carton",
                                            fileLink: nil, previewLink: nil, previewImage: nil) == "Boîte carton")
        #expect(InspirationKeys.mockupFolder(folderLink: nil,
                                            fileLink: "https://cloud.exemple.fr/remote.php/dav/files/u/Ressources/Mock-ups/Sac%20papier/sac.psd",
                                            previewLink: nil, previewImage: nil) == "Sac papier")
        #expect(InspirationKeys.mockupFolder(folderLink: nil, fileLink: nil, previewLink: nil, previewImage: "Tote bag.jpg") == "Tote bag")
        #expect(InspirationKeys.mockupFolder(folderLink: nil, fileLink: nil, previewLink: nil, previewImage: nil) == nil)
    }

    /// Run twice, it adds nothing, converts nothing and changes nothing.
    @Test func runningItTwiceAddsNothing() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let first = try await example.run()
        let files = try ExampleVault.snapshot(example.paths.inspiration)
        let second = try await example.run()
        for kind in InspirationKind.allCases {
            #expect(second[kind].added == 0 && second[kind].updated == 0)
            #expect(second[kind].unchanged == first[kind].added)
        }
        #expect(second.imagesConverted == 0 && second.bytesWritten == 0 && second.imagesReused == first.imagesConverted)
        #expect(second.imageBytes == first.imageBytes && second.summary == first.summary)
        #expect(try ExampleVault.snapshot(example.paths.inspiration) == files)
        #expect(try example.store.items(kind: .branding).count == 4)
    }

    /// The old copy n8n still writes to: what only it has comes in, the vault's own notes win the rest.
    @Test func theOldCopyFillsTheHole() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let report = try await example.run(extra: example.extra)
        #expect(report[.website].added == 8 && report[.website].onlyInExtra == 1)
        #expect(report[.branding].added == 5 && report[.branding].onlyInExtra == 1)
        let recent = try #require(try example.item(.website, titled: "Site Récent"))
        #expect(recent.images.count == 1 && recent.importedFrom == "database/Websites/Site Récent.md")
        #expect(try example.item(.branding, titled: "Nouvelle Marque")?.images.count == 1)
        // The vault's Café Nord wins: its categories, its three images, its text.
        let cafe = try #require(try example.store.item(kind: .branding, key: "7479089115955373553"))
        #expect(cafe.categories["secteur"] == ["restaurant"] && cafe.images.count == 3 && cafe.text.count > 100)
        // The vault's site keeps its large image.
        let site = try #require(try example.store.item(kind: .website, key: "https://studio-exemple.fr"))
        #expect(TestImages.Probe(example.imageURL(.website, site.images[0]))?.width == 1600)
    }

    /// The old copy chosen later: only what it adds comes in.
    @Test func theOldCopyChosenLaterOnlyAdds() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let report = try await example.run(extra: example.extra)
        #expect(report[.website].added == 1 && report[.website].updated == 0)
        #expect(report[.branding].added == 1 && report[.branding].updated == 0)
        #expect(report[.mockup].added == 0)
    }

    /// What Paul did in Polhub survives an import: his categories, a deleted item.
    @Test func paulsChoicesSurviveAnImport() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let site = try #require(try example.store.item(kind: .website, key: "https://studio-exemple.fr"))
        try example.store.setCategories(id: site.id, ["secteur": ["culture"]], at: Date())
        let home = try #require(try example.store.item(kind: .website, key: "https://exemple.fr"))
        try example.store.moveToTrash(id: home.id, at: Date())
        let cafe = try #require(try example.store.item(kind: .branding, key: "7479089115955373553"))
        try example.store.moveToTrash(id: cafe.id, at: Date())
        let report = try await example.run(extra: example.extra)
        #expect(try example.store.item(id: site.id)?.categories == ["secteur": ["culture"]])
        #expect(try example.store.items(kind: .website).contains { $0.id == home.id } == false)
        // Neither the post nor its duplicate comes back.
        #expect(try example.store.items(kind: .branding).contains { $0.title == "Café Nord" } == false)
        #expect(report[.branding].added == 1)
    }

    @Test func theProgressIsTold() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var steps: [(Int, Int)] = []
        }
        let box = Box()
        let report = try await example.run { done, total in box.lock.withLock { box.steps.append((done, total)) } }
        let steps = box.lock.withLock { box.steps }
        let total = report[.website].items + report[.branding].items + report[.mockup].items
        #expect(steps.last.map { $0 == (total, total) } == true)
        #expect(steps.map(\.0) == Array(1...total))
    }

    @Test func aCancelledImportStops() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let task = Task { try await example.run() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    /// The vault is only read: not a byte changes, nothing is added there.
    @Test func theVaultIsOnlyRead() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let before = try ExampleVault.snapshot(example.vault)
        let beforeExtra = try ExampleVault.snapshot(example.extra)
        _ = try await example.run(extra: example.extra)
        #expect(try ExampleVault.snapshot(example.vault) == before)
        #expect(try ExampleVault.snapshot(example.extra) == beforeExtra)
    }

    @Test func aFolderThatIsNotAVaultIsRefused() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let empty = example.root.appending(path: "vide", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await #expect(throws: InspirationImportError.self) {
            try await InspirationImport.run(vault: empty, database: example.database, paths: example.paths)
        }
        // An old copy that is not one is said, and the vault is imported all the same.
        let report = try await example.run(extra: empty)
        #expect(report[.website].added == 7 && report.warnings.contains { $0.contains("ancienne copie") })
    }

    /// The vault's live vocabulary (with a tag Paul added by hand) places that tag, and comes along into Polhub.
    @Test func theVaultsVocabularyComesAlong() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let bundled = try #require(InspirationVocabulary.bundledURL(.website))
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: bundled)) as! [String: Any]
        var style = json["style"] as! [String: String]
        style["fait-main"] = "ajouté à la main dans le coffre"
        json["style"] = style
        let folder = example.vault.appending(path: "obsidian/ia", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: folder.appending(path: "vocabulaire-websites.json"))
        _ = try await example.run()
        let atelier = try #require(try example.item(.website, titled: "Atelier Nord"))
        #expect(atelier.categories == ["secteur": ["culture"], "style": ["fait-main", "éditorial"], "support": ["éditorial"]])
        let copy = InspirationVocabulary.appCopy(.website, paths: example.paths)
        #expect(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
        #expect(InspirationVocabulary.load(.website, paths: example.paths).family("style")?.contains("fait-main") == true)
    }

    /// Unquoted `on`, `off`, `yes`, `no` (a hashtag #no, written bare by the vault's import) stay words, never
    /// « true » or « false »; `ia_manuel: true` still reads (review of 16/11).
    @Test func unquotedYesAndNoStayWords() throws {
        guard case .success(let read) = VaultFrontmatter.read("---\nhashtags:\n  - on\n  - no\n  - Yes\n  - off\nia_manuel: true\nautre: yes\n---\nCorps") else {
            Issue.record("illisible")
            return
        }
        #expect(VaultFrontmatter.list(read.properties["hashtags"]) == ["on", "no", "Yes", "off"])
        #expect(VaultFrontmatter.bool(read.properties["ia_manuel"]) && VaultFrontmatter.bool(read.properties["autre"]))
    }

    /// A LinkedIn page Paul no longer follows in Polhub is not followed again by the next import, though the
    /// vault's `_sources.md` (or the old copy's) still lists it (review of 16/11).
    @Test func aPageNoLongerFollowedStaysSo() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let galerie = try #require(try example.store.sources().first { $0.name == "Galerie Exemple" })
        try example.store.deleteSource(id: galerie.id, at: Date())
        let report = try await example.run(extra: example.extra)
        #expect(report.sourcesAdded == 0)
        #expect(try example.store.sources().map(\.name) == ["Atelier Exemple", "Revue Exemple"])
    }

    /// The duplicate of a post becomes the richer one and leads at the next import: the item gets that post's
    /// images, all of them, never mixed with the files of the post it was named after (review of 16/11).
    @Test func aReimportNeverMixesTheImagesOfTwoPosts() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        _ = try await example.run()
        let duplicate = "7481000460288173553", kept = "7479089115955373553"
        let media = example.vault.appending(path: "database/Branding/_media", directoryHint: .isDirectory)
        for (index, width) in [(3, 700), (4, 640), (5, 600)] {
            try TestImages.jpeg(width: width, height: 400).write(to: media.appending(path: "\(duplicate)-\(index).jpg"))
        }
        let note = example.vault.appending(path: "database/Branding/2026-07-09 Café Nord.md")
        let text = try String(contentsOf: note, encoding: .utf8).replacingOccurrences(
            of: "  - \"[[database/Branding/_media/\(duplicate)-2.jpg]]\"\n",
            with: (2...5).map { "  - \"[[database/Branding/_media/\(duplicate)-\($0).jpg]]\"\n" }.joined())
        try text.write(to: note, atomically: true, encoding: .utf8)
        _ = try await example.run()
        let cafe = try #require(try example.store.item(kind: .branding, key: kept))
        #expect(cafe.images == (1...5).map { InspirationImageName.branding(urn: kept, index: $0) })
        let widths = cafe.images.compactMap { TestImages.Probe(example.imageURL(.branding, $0))?.width }
        #expect(widths == [1000, 1000, 700, 640, 600])
    }

    /// The old copy only completes the vault: on a note both have, the vault's words and links win (Paul edited
    /// them there); a note only the old copy has, older than the vault's newest, may be one Paul deleted in
    /// Obsidian: it comes in, and is said (review of 16/11).
    @Test func theOldCopyNeverWinsOverTheVaultsWords() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let websites = example.extra.appending(path: "database/Websites", directoryHint: .isDirectory)
        let studio = websites.appending(path: "Studio Exemple — Design graphique.md")
        let longer = try String(contentsOf: studio, encoding: .utf8).replacingOccurrences(
            of: "description: \"Studio Exemple, design graphique et identités pour la culture.\"",
            with: "description: \"Studio Exemple, design graphique et identités pour la culture, dans une version plus ancienne et plus longue.\"")
        try longer.write(to: studio, atomically: true, encoding: .utf8)
        try """
        ---
        site: https://ancien-site.example.com/
        description: "Un site retiré du coffre vivant."
        date: 2026-09-15
        tags:
          - site
          - sotd
        ---
        """.write(to: websites.appending(path: "Ancien Site.md"), atomically: true, encoding: .utf8)
        let report = try await example.run(extra: example.extra)
        let site = try #require(try example.store.item(kind: .website, key: "https://studio-exemple.fr"))
        #expect(site.text == "Studio Exemple, design graphique et identités pour la culture.")
        #expect(try example.item(.website, titled: "Ancien Site") != nil)
        #expect(report.warnings.contains { $0.hasPrefix("« Ancien Site » :") && $0.contains("supprimée dans Obsidian") })
        // What only the old copy has since the vault's newest note is the hole: nothing said.
        #expect(!report.warnings.contains { $0.hasPrefix("« Site Récent » :") || $0.hasPrefix("« 2026-11-10 Nouvelle Marque » :") })
    }

    /// The weight is measured on the first conversions, before everything is converted: past the limit, the import
    /// stops and says how much it would have made (the design's « moins d'1 Go ; mesuré avant de tout convertir »).
    @Test func anImportThatWouldBeTooHeavyStopsEarly() async throws {
        let example = try ExampleVault()
        defer { example.remove() }
        let report = try await example.run(options: .init(imageBudget: 50_000, projectionAfter: 2))
        let projected = try #require(report.projectedBytes)
        #expect(projected > 50_000)
        #expect(report.imagesConverted < 13)
        #expect(report.summary.contains("import arrêté"))
        // Within the limit, nothing stops.
        let light = try ExampleVault()
        defer { light.remove() }
        let whole = try await light.run(options: .init(imageBudget: 1_000_000_000, projectionAfter: 2))
        #expect(whole.projectedBytes == nil && whole.imagesConverted == 13 && !whole.summary.contains("arrêté"))
    }

    @Test func theReportSaysItInOneLine() {
        var report = InspirationImportReport()
        report.counts[.website] = .init(added: 200, unchanged: 12)
        report.counts[.branding] = .init(added: 488)
        report.counts[.mockup] = .init(updated: 292)
        report.imageBytes = 640_000_000
        #expect(report.summary == "212 sites, 488 branding, 292 mock-ups ; 640 Mo d'images")
        report.counts = [.website: .init(added: 1), .branding: .init(added: 1), .mockup: .init(added: 1)]
        report.imageBytes = 1_240_000_000
        #expect(report.summary == "1 site, 1 branding, 1 mock-up ; 1\u{202F}240 Mo d'images")
        report.imageBytes = 0
        #expect(report.summary == "1 site, 1 branding, 1 mock-up ; aucune image")
    }
}
