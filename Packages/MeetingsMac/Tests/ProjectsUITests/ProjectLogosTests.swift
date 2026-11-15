import CoreGraphics
import Domain
import Foundation
import ImageIO
import Persistence
import PolhubDesign
import Testing
import UniformTypeIdentifiers
@testable import ProjectsUI

/// An image of `side` pixels, of one color, in the given kind: the fixtures of the logos, made here.
func imageBytes(_ type: UTType, side: Int) throws -> Data {
    let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// 15/11: the site of a project, the icon its home page names, what an icon may be. No network.
@Suite struct ProjectSitesTests {
    let alpha = UUID(), beta = UUID(), gamma = UUID()

    @Test func aTypedSiteBecomesItsName() {
        #expect(ProjectSites.domain("https://www.Exemple.fr/contact?x=1") == "www.exemple.fr")
        #expect(ProjectSites.domain(" exemple-studio.fr. ") == "exemple-studio.fr")
        #expect(ProjectSites.domain("http://exemple.fr:8080/") == "exemple.fr")
        #expect(ProjectSites.domain("192.168.1.20") == nil && ProjectSites.domain("localhost") == nil)
        #expect(ProjectSites.domain("nas.local") == nil && ProjectSites.domain("exemple") == nil && ProjectSites.domain("") == nil)
    }

    /// Everyone's mailboxes, Paul's own domain, a domain several projects share: none of them is a site.
    @Test func theSiteIsGuessedFromTheContactsOfThisProjectOnly() {
        let links = [
            ProjectSites.Link(email: "camille@atelier-exemple.fr", projectID: alpha),
            ProjectSites.Link(email: "jules@atelier-exemple.fr", projectID: alpha),
            ProjectSites.Link(email: "lea@autre-exemple.fr", projectID: alpha),
            ProjectSites.Link(email: "marc@gmail.com", projectID: beta),
            ProjectSites.Link(email: "paul@mon-studio.fr", projectID: beta),
            ProjectSites.Link(email: "nina@partage-exemple.fr", projectID: beta),
            ProjectSites.Link(email: "rose@partage-exemple.fr", projectID: gamma),
            ProjectSites.Link(email: "zoe@b-exemple.fr", projectID: gamma),
            ProjectSites.Link(email: "yves@a-exemple.fr", projectID: gamma),
        ]
        let guesses = ProjectSites.guesses(links, mine: ["paul@mon-studio.fr", "paul@gmail.com"])
        // The most frequent wins; a tie goes to the first by name.
        #expect(guesses == [alpha: "atelier-exemple.fr", gamma: "a-exemple.fr"])
    }

    @Test func theGuessesComeFromTheBase() throws {
        let database = try AppDatabase.inMemory()
        let now = Date()
        let project = try ProjectStore(database).addProject(name: "Atelier", status: .priorite1, at: now)
        let other = try ProjectStore(database).addProject(name: "Autre", status: .priorite2, at: now)
        let contacts = ContactStore(database)
        let camille = try contacts.upsert(email: "camille@atelier-exemple.fr", name: "Camille", company: nil, at: now)
        let removed = try contacts.upsert(email: "jo@retire-exemple.fr", name: "Jo", company: nil, at: now)
        let colleague = try contacts.upsert(email: "ana@mon-studio.fr", name: "Ana", company: nil, at: now)
        try contacts.link(contactID: camille.id, projectID: project.id, origin: .paul, at: now)
        try contacts.link(contactID: colleague.id, projectID: other.id, origin: .paul, at: now)
        try contacts.exclude(contactID: removed.id, projectID: other.id, at: now)
        try CalendarStore(database).addAccount(email: "paul@mon-studio.fr", at: now)
        #expect(try database.writer.read(ProjectLogos.readGuesses) == [project.id: "atelier-exemple.fr"])
    }

    @Test func theHomePageNamesItsIconsTheBestFirst() throws {
        let page = try #require(URL(string: "https://www.exemple.fr/accueil/"))
        let html = """
            <html><head>
            <link rel="icon" href="/favicon-16.png" sizes="16x16" type="image/png">
            <link rel="stylesheet" href="/style.css">
            <LINK REL="shortcut icon" HREF="favicon.ico">
            <link rel="icon" type="image/svg+xml" href="/icone.svg">
            <link rel="mask-icon" href="/masque.svg" color="#000">
            <link href="/touch-120.png" rel="apple-touch-icon" sizes="120x120">
            <link rel='apple-touch-icon' sizes='180x180' href='//cdn.exemple.fr/touch-180.png?v=1&amp;b=2'>
            <link rel="icon" href="http://exemple.fr/pas-chiffre.png">
            <link rel="icon" href="data:image/png;base64,AAAA">
            <link rel="icon" href="/favicon-96.png" sizes="96x96">
            </head><body></body></html>
            """
        #expect(FaviconParser.candidates(html: html, page: page).map(\.absoluteString) == [
            "https://cdn.exemple.fr/touch-180.png?v=1&b=2", "https://www.exemple.fr/touch-120.png",
            "https://www.exemple.fr/favicon-96.png", "https://www.exemple.fr/favicon-16.png",
            "https://www.exemple.fr/accueil/favicon.ico", "https://www.exemple.fr/favicon.ico",
        ])
    }

    @Test func aBaseTagAndAPageWithoutIcons() throws {
        let page = try #require(URL(string: "https://exemple.fr/"))
        #expect(FaviconParser.candidates(html: "<p>Rien</p>", page: page).map(\.absoluteString) == ["https://exemple.fr/favicon.ico"])
        let based = #"<base href="https://statique.exemple.fr/v2/"><link rel="icon" href="logo.png">"#
        #expect(FaviconParser.candidates(html: based, page: page).first?.absoluteString == "https://statique.exemple.fr/v2/logo.png")
    }

    /// PNG, ICO, JPEG, GIF only, a megabyte at most, 32 pixels at least; always kept as a PNG.
    @Test func onlyFourKindsOfIconsAreTaken() throws {
        for type in [UTType.png, .jpeg, .gif, .ico] {
            let png = try #require(LogoImage.png(fromWeb: try imageBytes(type, side: 64)), "\(type.identifier)")
            #expect(LogoImage.type(of: png) == UTType.png.identifier)
        }
        #expect(LogoImage.png(fromWeb: try imageBytes(.tiff, side: 64)) == nil)
        #expect(LogoImage.png(fromWeb: try imageBytes(.png, side: 16)) == nil)
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64"/></svg>"#.utf8)
        #expect(LogoImage.png(fromWeb: svg) == nil)
        #expect(LogoImage.png(fromWeb: Data("<html>pas une image</html>".utf8)) == nil)
        var heavy = try imageBytes(.png, side: 64)
        heavy.append(Data(count: LogoImage.maxWebBytes))
        #expect(LogoImage.png(fromWeb: heavy) == nil)
        // Paul's own image may be of any kind ImageIO reads, and small.
        #expect(LogoImage.png(fromFile: try imageBytes(.tiff, side: 20)) != nil)
    }

    @Test func aLargeImageIsKeptAt256Pixels() throws {
        let png = try #require(LogoImage.png(fromWeb: try imageBytes(.png, side: 600)))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 256)
    }
}

/// A site that answers what it is told, and counts the questions.
actor FakeSites: LogoFetching {
    private(set) var asked: [String] = []
    private(set) var answers: [String: Data]
    /// Called at each question, before the answer.
    var onAsk: (@Sendable (String) -> Void)?

    init(_ answers: [String: Data]) {
        self.answers = answers
    }

    func answer(_ domain: String, with data: Data?) {
        answers[domain] = data
    }

    func whenAsked(_ action: @escaping @Sendable (String) -> Void) {
        onAsk = action
    }

    func logo(for domain: String) async -> Data? {
        asked.append(domain)
        onAsk?(domain)
        return answers[domain]
    }
}

/// A clock the test moves.
final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_794_700_000)
}

@MainActor @Suite struct ProjectLogosTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "logos \(UUID().uuidString)", directoryHint: .isDirectory)
    let clock = TestClock()

    func logos(_ sites: FakeSites, defaults: UserDefaults? = nil) throws -> ProjectLogos {
        let defaults = try defaults ?? #require(UserDefaults(suiteName: "logos-\(UUID().uuidString)"))
        return ProjectLogos(folder: folder, database: nil, fetcher: sites, defaults: defaults, now: { [clock] in clock.now })
    }

    func project(_ status: ProjectStatus = .priorite1) -> ProjectRow {
        ProjectRow(name: "Atelier Nord", status: status, createdAt: clock.now)
    }

    func sites() throws -> [String: SiteEntry] {
        try JSONDecoder().decode([String: SiteEntry].self, from: Data(contentsOf: folder.appending(path: "sites.json")))
    }

    @Test func aTypedSiteIsAskedOnceThenKept() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let icon = try #require(LogoImage.png(fromWeb: try imageBytes(.png, side: 64)))
        let sites = FakeSites(["exemple.fr": icon])
        let logos = try logos(sites)
        let project = project()
        logos.setSite("https://exemple.fr/", for: project.id)
        #expect(logos.site(for: project.id) == ProjectSite(domain: "exemple.fr", guessed: false))
        #expect(logos.image(for: project, online: true) == nil)
        logos.request(project)
        await logos.settle()
        #expect(logos.image(for: project, online: true) != nil && logos.image(for: project, online: false) == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "exemple.fr.png").path(percentEncoded: false)))
        // Shown again the next day: not asked again within the week.
        clock.now += 86_400
        logos.request(project)
        await logos.settle()
        #expect(await sites.asked == ["exemple.fr"])
        clock.now += 7 * 86_400
        logos.request(project)
        await logos.settle()
        #expect(await sites.asked == ["exemple.fr", "exemple.fr"])
        #expect(try self.sites()[project.id.uuidString.lowercased()] == SiteEntry(site: "exemple.fr", source: .chosen))
    }

    @Test func aSiteWithoutIconIsAskedAgainTheNextDay() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sites = FakeSites([:])
        let logos = try logos(sites)
        let project = project()
        logos.setSite("exemple.fr", for: project.id)
        logos.request(project)
        await logos.settle()
        clock.now += 3_600
        logos.request(project)
        await logos.settle()
        #expect(await sites.asked.count == 1 && logos.image(for: project, online: true) == nil)
        clock.now += 86_400
        logos.request(project)
        await logos.settle()
        #expect(await sites.asked.count == 2)
    }

    /// Never for a project Terminé, never with the setting off.
    @Test func nothingIsAskedForTerminéOrWithTheLogosOff() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sites = FakeSites([:])
        let defaults = try #require(UserDefaults(suiteName: "logos-coupes-\(UUID().uuidString)"))
        let logos = try logos(sites, defaults: defaults)
        let done = project(.termine)
        logos.setSite("exemple.fr", for: done.id)
        logos.request(done)
        defaults.set(false, forKey: Preferences.Key.projectLogos)
        let open = project()
        logos.setSite("exemple-studio.fr", for: open.id)
        logos.request(open)
        await logos.settle()
        #expect(await sites.asked.isEmpty)
    }

    /// Paul's image wins over the site's icon, even with the logos off; taken away, the site comes back.
    @Test func paulsImageWins() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let logos = try logos(FakeSites([:]))
        let project = project()
        logos.setSite("exemple.fr", for: project.id)
        #expect(logos.setImage(data: try imageBytes(.tiff, side: 80), for: project.id))
        #expect(logos.hasOwnImage(project.id) && logos.image(for: project, online: false) != nil)
        #expect(try sites()[project.id.uuidString.lowercased()] == SiteEntry(site: "exemple.fr", source: .image))
        #expect(!logos.setImage(data: Data("pas une image".utf8), for: UUID()))
        logos.removeImage(for: project.id)
        #expect(!logos.hasOwnImage(project.id) && logos.image(for: project, online: false) == nil)
        #expect(logos.site(for: project.id) == ProjectSite(domain: "exemple.fr", guessed: false))
    }

    /// The guess shows as such, is kept in `sites.json`, and gives way to what Paul types; « no site » is a choice.
    @Test func aGuessGivesWayToPaul() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let logos = try logos(FakeSites([:]))
        let id = UUID()
        logos.apply(guesses: [id: "atelier-exemple.fr"])
        #expect(logos.site(for: id) == ProjectSite(domain: "atelier-exemple.fr", guessed: true))
        #expect(try sites()[id.uuidString.lowercased()] == SiteEntry(site: "atelier-exemple.fr", source: .guessed))
        logos.setSite("", for: id)
        #expect(logos.site(for: id) == nil)
        logos.apply(guesses: [id: "autre-exemple.fr"])
        #expect(logos.site(for: id) == nil)
        logos.clearSite(for: id)
        #expect(logos.site(for: id) == ProjectSite(domain: "autre-exemple.fr", guessed: true))
        logos.apply(guesses: [:])
        #expect(try sites().isEmpty && logos.site(for: id) == nil)
        // What was written is read again at the next launch.
        logos.setSite("exemple.fr", for: id)
        let again = ProjectLogos(folder: folder, database: nil, fetcher: FakeSites([:]))
        #expect(again.site(for: id) == ProjectSite(domain: "exemple.fr", guessed: false))
    }

    /// « Rafraîchir les logos »: the sites are asked again; Paul's images stay.
    @Test func refreshingAsksTheSitesAgain() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let icon = try #require(LogoImage.png(fromWeb: try imageBytes(.png, side: 64)))
        let sites = FakeSites(["exemple.fr": icon])
        let logos = try logos(sites)
        let shown = project()
        let own = project()
        logos.setSite("exemple.fr", for: shown.id)
        logos.setImage(data: try imageBytes(.png, side: 40), for: own.id)
        logos.request(shown)
        await logos.settle()
        logos.refreshAll()
        #expect(logos.image(for: own, online: true) != nil)
        logos.request(shown)
        await logos.settle()
        #expect(await sites.asked.count == 2 && logos.image(for: shown, online: true) != nil)
    }

    /// Correctifs du 15/11 : rafraîchir hors ligne, ou quand le site du client est en panne, garde l'ancien logo
    /// au lieu de laisser les initiales un jour entier.
    @Test func refreshingKeepsTheOldIconUntilANewOneComes() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let icon = try #require(LogoImage.png(fromWeb: try imageBytes(.png, side: 64)))
        let sites = FakeSites(["exemple.fr": icon])
        let logos = try logos(sites)
        let project = project()
        logos.setSite("exemple.fr", for: project.id)
        logos.request(project)
        await logos.settle()
        await sites.answer("exemple.fr", with: nil)
        logos.refresh(project)
        await logos.settle()
        #expect(await sites.asked.count == 2)
        #expect(logos.image(for: project, online: true) != nil)
        logos.refreshAll()
        logos.request(project)
        await logos.settle()
        #expect(await sites.asked.count == 3)
        #expect(logos.image(for: project, online: true) != nil)
    }

    /// Correctifs du 15/11 : couper « Logos des sites des clients » arrête aussi les sites déjà en attente.
    @Test func turningTheLogosOffStopsTheSitesAlreadyQueued() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let sites = FakeSites([:])
        let defaults = try #require(UserDefaults(suiteName: "logos-coupes-en-route-\(UUID().uuidString)"))
        nonisolated(unsafe) let shared = defaults
        await sites.whenAsked { _ in shared.set(false, forKey: Preferences.Key.projectLogos) }
        let logos = try logos(sites, defaults: defaults)
        let first = project(), second = project()
        logos.setSite("exemple.fr", for: first.id)
        logos.setSite("exemple-studio.fr", for: second.id)
        logos.request(first)
        logos.request(second)
        await logos.settle()
        #expect(await sites.asked == ["exemple.fr"])
    }

    /// Correctifs du 15/11 : un site tapé qui n'est pas un nom de site ne devient jamais un nom de fichier, ni une
    /// question à un site ; « Rafraîchir » n'efface rien hors de `Logos/`.
    @Test func aTypedSiteThatIsNotADomainIsNeverAFile() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "logos-chemin \(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let neighbour = base.appending(path: "maquettes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: neighbour, withIntermediateDirectories: true)
        let victim = neighbour.appending(path: "logo.png")
        try imageBytes(.png, side: 64).write(to: victim)
        let sites = FakeSites([:])
        let defaults = try #require(UserDefaults(suiteName: "logos-chemin-\(UUID().uuidString)"))
        let logos = ProjectLogos(folder: base.appending(path: "Logos", directoryHint: .isDirectory), database: nil, fetcher: sites,
                                 defaults: defaults, now: { [clock] in clock.now })
        let project = project()
        logos.setSite("../maquettes/logo", for: project.id)
        #expect(logos.image(for: project, online: true) == nil)
        logos.request(project)
        await logos.settle()
        logos.refresh(project)
        await logos.settle()
        logos.refreshAll()
        #expect(await sites.asked.isEmpty)
        #expect(FileManager.default.fileExists(atPath: victim.path(percentEncoded: false)))
    }

    /// Correctifs du 15/11 : « Changer » sur un site deviné, puis Entrée sans rien changer, garde le site deviné ;
    /// l'effacer est le seul moyen de dire « pas de site ».
    @Test func savingTheGuessUnchangedKeepsItAGuess() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let logos = try logos(FakeSites([:]))
        let id = UUID()
        logos.apply(guesses: [id: "atelier-exemple.fr"])
        logos.setSite(" atelier-exemple.fr ", for: id)
        #expect(logos.site(for: id) == ProjectSite(domain: "atelier-exemple.fr", guessed: true))
        #expect(logos.entries[id]?.source == .guessed)
        // Nothing there and nothing typed: nothing changes either.
        let other = UUID()
        logos.setSite("", for: other)
        #expect(logos.entries[other] == nil)
        logos.setSite("", for: id)
        #expect(logos.site(for: id) == nil)
    }

    /// Correctifs du 15/11 : seul un fichier image, et de 20 Mo au plus, devient le logo ; une adresse web glissée
    /// depuis un navigateur ou un énorme fichier sont refusés sans être lus.
    @Test func onlyAnImageFileOfTwentyMegabytesAtMostIsTaken() async throws {
        let files = FileManager.default.temporaryDirectory.appending(path: "logos-fichiers \(UUID().uuidString)", directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: files)
            try? FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let logos = try logos(FakeSites([:]))
        let id = UUID()
        #expect(await !logos.setImage(from: try #require(URL(string: "https://exemple.fr/logo.png")), for: id))
        let text = files.appending(path: "notes.txt")
        try Data("pas une image".utf8).write(to: text)
        #expect(await !logos.setImage(from: text, for: id))
        let huge = files.appending(path: "enorme.png")
        #expect(FileManager.default.createFile(atPath: huge.path(percentEncoded: false), contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(LogoImage.maxFileBytes + 1))
        try handle.close()
        #expect(await !logos.setImage(from: huge, for: id))
        #expect(!logos.hasOwnImage(id))
        let image = files.appending(path: "logo.png")
        try imageBytes(.png, side: 80).write(to: image)
        #expect(await logos.setImage(from: image, for: id))
        #expect(logos.hasOwnImage(id))
    }
}
