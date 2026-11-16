import Foundation
import Persistence
import Testing
@testable import Inspiration

/// How the collection reads the public pages (16/11): Awwwards' home, a site's OpenGraph tags, a LinkedIn company
/// page and a post's embed page. Recorded, invented pages that keep the real structure.
@Suite struct WebPageParsingTests {
    @Test func awwwardsHomeGivesTheSiteOfTheDayItsThumbnailAndPage() throws {
        let home = try #require(AwwwardsHome.parse(CollectFixtures.html("awwwards-accueil.html")))
        // The « Visit Sotd. » link, without its fragment; never Awwwards' own links nor the conference.
        #expect(home.site.absoluteString == CollectFixtures.lumiere)
        #expect(home.thumbnail?.absoluteString == CollectFixtures.awwwardsThumbnail)
        #expect(home.page?.absoluteString == "https://www.awwwards.com/sites/lumiere-exemple")
    }

    @Test func awwwardsHomeWithoutTheLinkGivesNothing() {
        #expect(AwwwardsHome.parse("<html><body><a href=\"https://www.awwwards.com/\">Visit Sotd.</a></body></html>") == nil)
        #expect(AwwwardsHome.parse("<html><body><p>Maintenance</p></body></html>") == nil)
        // Protocol-relative, as n8n accepted it.
        let relative = AwwwardsHome.parse("<a class='x' href=\"//site.exemple.fr/\">Visit Sotd</a>")
        #expect(relative?.site.absoluteString == "https://site.exemple.fr/")
    }

    /// og tags whatever the order of their attributes, entities decoded, the head before the body; Twitter's and
    /// `<title>` only behind them.
    @Test func openGraphReadsTheHead() {
        let graph = OpenGraph.parse(CollectFixtures.html("site-lumiere.html"))
        #expect(graph.title == "Lumière Exemple — Studio d'éclairage")
        #expect(graph.description == "Un studio d'éclairage qui dessine la lumière des lieux culturels : effets WebGL, défilement fluide et typographie éditoriale.")
        #expect(graph.image == "/images/partage.jpg")
        let base = URL(string: CollectFixtures.lumiere)!
        #expect(graph.imageURL(base: base)?.absoluteString == CollectFixtures.lumiereImage)
        let bare = OpenGraph.parse(CollectFixtures.html("site-sans-image.html"))
        #expect(bare.title == "Atelier Exemple | Portfolio")
        #expect(bare.description == "Le portfolio d'un atelier de design graphique et de signalétique, à Nantes.")
    }

    /// An og:image on `localhost`, a private address, `file:` or `data:` is never fetched.
    @Test func aLocalImageIsRefused() {
        let base = URL(string: "https://atelier.exemple.fr/")!
        for image in ["http://localhost:3000/og.png", "http://192.168.1.20/og.jpg", "https://10.0.0.4/og.jpg", "file:///etc/hosts",
                      "data:image/png;base64,AAAA", "http://127.0.0.1/og.png", "https://intranet.local/og.png", "http://[::1]/og.png"] {
            #expect(OpenGraph(image: image).imageURL(base: base) == nil, "\(image)")
        }
        #expect(OpenGraph(image: "//cdn.exemple.fr/og.jpg").imageURL(base: base)?.absoluteString == "https://cdn.exemple.fr/og.jpg")
        #expect(OpenGraph(image: "og.jpg").imageURL(base: URL(string: "https://atelier.exemple.fr/projets/")!)?.absoluteString
            == "https://atelier.exemple.fr/projets/og.jpg")
    }

    @Test func onlyThePublicWebIsRead() {
        for address in ["https://exemple.fr/", "http://example.com/a?b=c", "https://8.8.8.8/", "https://exemple.fr:8443/x"] {
            #expect(PublicWeb.isAllowed(URL(string: address)!), "\(address)")
        }
        for address in ["file:///Users/x", "ftp://exemple.fr/", "http://localhost/", "http://machine/", "http://10.1.2.3/",
                        "http://172.20.0.1/", "http://169.254.169.254/latest", "http://100.64.0.1/", "http://0x7f.1/",
                        "https://user:secret@exemple.fr/", "http://imprimante.local/", "http://[fe80::1]/", "http://2130706433/"] {
            #expect(!PublicWeb.isAllowed(URL(string: address)!), "\(address)")
        }
        #expect(PublicWeb.secure(URL(string: "http://exemple.fr/a")!).absoluteString == "https://exemple.fr/a")
    }

    // MARK: - LinkedIn

    @Test func aCompanyPageGivesItsPostsByUrn() throws {
        guard case .posts(let articles) = LinkedInPublic.companyPage(CollectFixtures.html("linkedin-entreprise.html"),
                                                                     url: URL(string: CollectFixtures.studioPage)) else {
            Issue.record("pas de posts")
            return
        }
        #expect(articles.map(\.urn) == [CollectFixtures.cafeUrn, CollectFixtures.knownUrn, CollectFixtures.marqueUrn])
        let card = LinkedInPublic.content(of: articles[0])
        #expect(card.text.hasPrefix("Café Lumière by Atelier Nord\nUne identité chaleureuse pour un café de quartier."))
        // The post's images only: never the page's logo.
        #expect(card.images == [CollectFixtures.media("D4E22AQExemple11", "feedshare-shrink_800", "carte11"),
                                CollectFixtures.media("D4E22AQExemple12", "feedshare-shrink_800", "carte12")])
        // Without LinkedIn's tracking.
        #expect(card.links == ["https://exemple.fr/cafe-lumiere"])
        // A video's cover is not a post image (`videocover`), the card's image is.
        let marque = LinkedInPublic.content(of: articles[2])
        #expect(marque.images == [CollectFixtures.media("D4E22AQExemple31", "feedshare-shrink_800", "carte31")])
    }

    @Test func aLoginWallIsRecognised() {
        #expect(LinkedInPublic.companyPage(CollectFixtures.html("linkedin-mur.html"), url: URL(string: CollectFixtures.studioPage)) == .loginWall)
        #expect(LinkedInPublic.companyPage("<html></html>", url: URL(string: "https://www.linkedin.com/authwall?trk=x")) == .loginWall)
        #expect(LinkedInPublic.companyPage("<html><body><p>Rien</p></body></html>", url: URL(string: CollectFixtures.studioPage)) == .noPosts)
    }

    /// The embed page: the whole text, the best variant of each image (never the logo), the links of the text
    /// only (never LinkedIn's chrome nor the post itself).
    @Test func anEmbedPageGivesTheWholePost() throws {
        let embed = try #require(LinkedInPublic.embed(CollectFixtures.html("linkedin-embed.html"),
                                                      url: CollectFixtures.embed(CollectFixtures.cafeUrn).asURL, urn: CollectFixtures.cafeUrn))
        #expect(embed.text.hasPrefix("Café Lumière by Atelier Nord\nUne identité chaleureuse pour un café de quartier à Lyon"))
        #expect(embed.text.contains("L'atelier a aussi dessiné le site et les affiches de l’ouverture"))
        #expect(embed.images.count == 6)
        #expect(embed.images.first == CollectFixtures.media("D4E22AQExemple10", "feedshare-shrink_2048_1536", "embed10"))
        // The page that posted it is still there: the collection drops it, knowing the page.
        #expect(embed.links == ["https://www.linkedin.com/company/studio-exemple", "https://exemple.fr/cafe-lumiere",
                                "https://www.linkedin.com/company/atelier-nord/"])
        #expect(LinkedInPublic.embed(CollectFixtures.html("linkedin-mur.html"), url: nil, urn: CollectFixtures.cafeUrn) == nil)
    }

    @Test func theBestVariantOfEachImageWins() {
        let images = LinkedInPublic.bestImages([
            CollectFixtures.media("A1", "feedshare-shrink_800", "a"),
            CollectFixtures.media("B2", "feedshare-shrink_800", "b"),
            CollectFixtures.media("A1", "feedshare-shrink_2048_1536", "c"),
            CollectFixtures.media("C3", "company-logo_100_100", "d"),
            CollectFixtures.media("D4", "profile-displayphoto-shrink_100_100", "e"),
            CollectFixtures.media("E5", "articleshare-shrink_800", "f"),
            CollectFixtures.media("F6", "article-cover_image-shrink_720_1280", "g"),
        ])
        #expect(images == [CollectFixtures.media("A1", "feedshare-shrink_2048_1536", "c"), CollectFixtures.media("B2", "feedshare-shrink_800", "b"),
                           CollectFixtures.media("F6", "article-cover_image-shrink_720_1280", "g")])
    }

    @Test func linkedInsChromeIsNotAPostLink() {
        let urn = CollectFixtures.cafeUrn
        for link in ["https://static.licdn.com/x.css", "https://www.linkedin.com/feed/update/urn:li:activity:\(urn)/",
                     "https://www.linkedin.com/legal/user-agreement", "https://www.linkedin.com/", "https://fr.linkedin.com/signup/cold-join",
                     "https://www.linkedin.com/company/studio-exemple/posts/"] {
            #expect(LinkedInPublic.isChrome(link, urn: urn), "\(link)")
        }
        for link in ["https://exemple.fr/projet", "https://www.linkedin.com/company/atelier-nord/", "https://www.linkedin.com/in/une-designer"] {
            #expect(!LinkedInPublic.isChrome(link, urn: urn), "\(link)")
        }
        #expect(LinkedInPublic.cleanLink("https://www.linkedin.com/company/atelier-nord/?trk=x") == "https://www.linkedin.com/company/atelier-nord/")
        #expect(LinkedInPublic.cleanLink("https://www.linkedin.com/feed/hashtag/branding") == nil)
        #expect(LinkedInPublic.cleanLink("javascript:void(0)") == nil)
        #expect(LinkedInPublic.cleanLink("https://exemple.fr/?ref=linkedin") == "https://exemple.fr/?ref=linkedin")
    }

    /// The title is the first line before « by », the studio after it; the hashtags are gathered, their closing
    /// lines taken off the text.
    @Test func aPostIsDerivedAsTheVaultDidIt() {
        let post = LinkedInPublic.post(
            text: "Café Lumière by Atelier Nord 🎨 :\nUne identité chaleureuse https://exemple.fr\n\nhashtag#branding hashtag #Identite\n#café #2026",
            links: ["https://www.linkedin.com/company/atelier-nord/", "https://exemple.fr/cafe"], urn: "123456789")
        #expect(post.title == "Café Lumière")
        #expect(post.studio == "Atelier Nord 🎨")
        #expect(post.body == "Café Lumière by Atelier Nord 🎨 :\nUne identité chaleureuse https://exemple.fr")
        #expect(post.hashtags == ["branding", "identite", "café"])
        #expect(post.links == ["https://exemple.fr/cafe", "https://www.linkedin.com/company/atelier-nord/"])
        let bare = LinkedInPublic.post(text: "#branding", links: [], urn: "42424242")
        #expect(bare.title == "Publication 42424242" && bare.studio == nil && bare.body.isEmpty)
        let seeMore = LinkedInPublic.post(text: "Nouvelle identité pour une brasserie\n… voir plus", links: [], urn: "1")
        #expect(seeMore.body == "Nouvelle identité pour une brasserie" && seeMore.studio == nil)
    }

    /// A last line of many hashtags that ends with something else (a full stop, a hyphenated tag), or a run of
    /// spaces, is read at once: the patterns used to try every way of sharing the spaces, seconds for 13 hashtags,
    /// hours for 20, and a meeting could not stop them (review of 16/11).
    @Test func aLongLineOfHashtagsIsReadAtOnce() {
        let hashtags = 30, spaces = 2_000
        let tags = (1...hashtags).map { "#marque\($0)" }.joined(separator: " ")
        let start = ContinuousClock.now
        let dot = LinkedInPublic.post(text: "Café Lumière by Atelier Nord\nUne identité.\n\(tags) .", links: [], urn: "1")
        let hyphen = LinkedInPublic.post(text: "Café Lumière\n\(tags) #brand-identity", links: [], urn: "2")
        let blank = LinkedInPublic.post(text: "Café Lumière" + String(repeating: " ", count: spaces) + "x", links: [], urn: "3")
        let trailing = LinkedInPublic.post(text: "Café Lumière\n" + String(repeating: " ", count: spaces), links: [], urn: "4")
        #expect(ContinuousClock.now - start < .seconds(1))
        // Not made only of hashtags: the line stays; the hashtags are still gathered.
        #expect(dot.body.hasSuffix("\(tags) .") && dot.hashtags.count == hashtags && dot.title == "Café Lumière")
        #expect(hyphen.body.hasSuffix("#brand-identity"))
        #expect(blank.title == "Café Lumière x" && trailing.body == "Café Lumière")
        // As before: lines of hashtags only go, glued or not, and « see more » in any case.
        #expect(LinkedInPublic.post(text: "Titre\n#a #b\t#c  \n#d#e", links: [], urn: "5").body == "Titre")
        #expect(LinkedInPublic.post(text: "Titre\n##a", links: [], urn: "6").body == "Titre\n##a")
        #expect(LinkedInPublic.post(text: "Une brasserie\nSEE MORE   ", links: [], urn: "7").body == "Une brasserie")
        #expect(LinkedInPublic.post(text: "Une brasserie …afficher plus", links: [], urn: "8").body == "Une brasserie")
    }

    @Test func entitiesAreDecoded() {
        #expect(HTMLScan.decode("L&#39;atelier &amp; la &quot;lumière&quot; &eacute;t&#xE9; &unknown; &") == "L'atelier & la \"lumière\" été &unknown; &")
        #expect(HTMLScan.text("<p>Un<br/>deux&nbsp;trois</p><p>quatre</p>") == "Un\ndeux trois\nquatre")
    }
}

extension String {
    var asURL: URL? { URL(string: self) }
}
