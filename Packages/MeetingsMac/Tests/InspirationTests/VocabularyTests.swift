import Foundation
import Persistence
import Testing
@testable import Inspiration

/// The categories' vocabularies (16/11): the two the vault had, bundled with Polhub, and the mock-ups' types.
@Suite struct VocabularyTests {
    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vocabulaire \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func theBundledVocabulariesHaveTheVaultsFamilies() throws {
        let websites = try InspirationVocabulary.bundled(.website)
        #expect(websites.families.map(\.name) == ["secteur", "style", "techno", "typo", "support"])
        #expect(websites.version == 1 && websites.minimumWords == 8 && websites.origin == .bundled)
        let branding = try InspirationVocabulary.bundled(.branding)
        #expect(branding.families.map(\.name) == ["secteur", "style", "typo", "support"])
        #expect(branding.minimumWords == 40 && branding.fixedTags == ["branding"] && branding.sourceTagProperty == "source")
        let mockups = try InspirationVocabulary.bundled(.mockup)
        #expect(mockups.families.map(\.name) == [InspirationVocabulary.typeFamily])
        #expect(mockups.family("type")?.contains("business card") == true && mockups.family("type")?.contains("boite aux lettres") == true)
    }

    /// The tags keep the file's order (the menus show them so), each with its French description.
    @Test func theTagsKeepTheirOrderAndDescription() throws {
        let websites = try InspirationVocabulary.bundled(.website)
        let secteur = try #require(websites.family("secteur"))
        #expect(secteur.tags.prefix(3).map(\.value) == ["agence", "portfolio", "produit"])
        #expect(secteur.tags.last?.value == "autre")
        #expect(secteur.minimum == 1 && secteur.maximum == 2 && secteur.title == "Secteur")
        #expect(websites.family("style")?.description(of: "minimal") == "épuré, beaucoup de blanc, peu d'éléments")
        #expect(websites.minimumTotal == 2 && websites.maximumTotal == 8)
        #expect(websites.trimOrder == ["techno", "style", "typo", "support", "secteur"])
        let branding = try InspirationVocabulary.bundled(.branding)
        #expect(branding.family("secteur")?.tags.first?.value == "restaurant")
        #expect(branding.family("support")?.tags.map(\.value).contains("packaging") == true)
    }

    /// The prompt's pieces, for the tagger: what is classified, the rules, each family, fonts and client.
    @Test func thePromptPiecesAreThere() throws {
        let branding = try InspirationVocabulary.bundled(.branding)
        let prompt = try #require(branding.prompt)
        #expect(prompt.subject.hasPrefix("branding case studies"))
        #expect(prompt.rules.count == 1 && !prompt.fonts.isEmpty && !prompt.client.isEmpty && !prompt.suffix.isEmpty && !prompt.reminder.isEmpty)
        #expect(branding.family("typo")?.prompt == "the typography, only when described.")
        #expect(branding.header.map(\.label) == ["Brand", "Studio"] && branding.header.map(\.property) == ["titre", "studio"])
        #expect(branding.ignoredLines == ["[Voir sur LinkedIn]"])
        let instructions = try #require(branding.instructions)
        #expect(instructions.contains("- \"secteur\" (1-2): the client's business"))
        #expect(instructions.contains("  restaurant: restaurant, bar, café"))
        #expect(try InspirationVocabulary.bundled(.mockup).instructions == nil)
    }

    /// What is submitted to the tagger: the header from the properties, then the body without embeds nor the
    /// ignored lines, links reduced to their text; too short, it is not submitted.
    @Test func theTextForTheTaggerIsPreparedAsTheVaultDid() throws {
        let branding = try InspirationVocabulary.bundled(.branding)
        let text = branding.taggingText(fields: ["titre": "Café Nord", "studio": "Atelier Nord"], body: """
            Une identité chaleureuse pour un café de quartier, voir [le site](https://exemple.fr).
            ![[database/Branding/_media/1-1.jpg]]

            [Voir sur LinkedIn](https://www.linkedin.com/feed/update/urn:li:activity:1/)
            """)
        #expect(text == "Brand: Café Nord\nStudio: Atelier Nord\n\nUne identité chaleureuse pour un café de quartier, voir le site.")
        #expect(branding.isTooShort(text))
        let websites = try InspirationVocabulary.bundled(.website)
        #expect(!websites.isTooShort("Title: Exemple\nSite: https://exemple.fr\n\nUn studio de design graphique installé à Nantes, en France."))
    }

    /// Polhub's own copy (the vault's, with the tags Paul added by hand) comes before the bundled one; a broken copy
    /// is passed over.
    @Test func polhubsOwnCopyComesBeforeTheBundledOne() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root, logs: root.appending(path: "Logs"))
        try FileManager.default.createDirectory(at: paths.inspiration, withIntermediateDirectories: true)
        let bundledURL = try #require(InspirationVocabulary.bundledURL(.branding))
        try FileManager.default.copyItem(at: bundledURL, to: InspirationVocabulary.appCopy(.branding, paths: paths))
        #expect(InspirationVocabulary.load(.branding, paths: paths).origin == .app(InspirationVocabulary.appCopy(.branding, paths: paths)))
        #expect(InspirationVocabulary.load(.website, paths: paths).origin == .bundled)
        try Data("{ pas du json".utf8).write(to: InspirationVocabulary.appCopy(.branding, paths: paths))
        #expect(InspirationVocabulary.load(.branding, paths: paths).origin == .bundled)
    }

    /// The bundled files carry no `_doc` (it names machines): only design words go public.
    @Test func theBundledFilesCarryNoDoc() throws {
        for kind in InspirationKind.allCases {
            let url = try #require(InspirationVocabulary.bundledURL(kind))
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            #expect(json["_doc"] == nil)
        }
    }
}
