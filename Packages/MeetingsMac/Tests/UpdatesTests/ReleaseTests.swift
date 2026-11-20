import Foundation
import Testing
@testable import Updates

@Suite struct ReleaseTests {
    @Test func versionsCompareNumerically() throws {
        let a = try #require(SemanticVersion("0.10.0")), b = try #require(SemanticVersion("0.9.9"))
        #expect(a > b && SemanticVersion("1.0.0")! > SemanticVersion("0.99.99")!)
        #expect(SemanticVersion("0.3") == nil && SemanticVersion("abc") == nil)
        #expect(a.description == "0.10.0")
    }

    @Test func aLeadingVIsAccepted() {
        #expect(SemanticVersion("v0.3.1") == SemanticVersion("0.3.1"))
    }

    static let json = """
    [
      {"tag_name": "v0.3.2", "draft": true, "prerelease": false, "body": "brouillon", "published_at": null,
       "assets": [{"name": "Polhub.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.3.2/Polhub.zip"}]},
      {"tag_name": "v0.3.1", "draft": false, "prerelease": false, "body": "Corrections.", "published_at": "2026-11-14T09:00:00Z",
       "assets": [{"name": "Polhub.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.3.1/Polhub.zip"}]},
      {"tag_name": "v0.4.0-beta", "draft": false, "prerelease": true, "body": "", "published_at": "2026-11-14T10:00:00Z",
       "assets": [{"name": "Polhub.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.4.0-beta/Polhub.zip"}]},
      {"tag_name": "v0.3.3", "draft": false, "prerelease": false, "body": "Sans archive.", "published_at": "2026-11-14T11:00:00Z",
       "assets": [{"name": "autre.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.3.3/autre.zip"}]},
      {"tag_name": "v0.3.0", "draft": false, "prerelease": false, "body": "Première version.", "published_at": "2026-11-13T18:00:00Z",
       "assets": [{"name": "Polhub.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.3.0/Polhub.zip"}]}
    ]
    """

    @Test func draftsPrereleasesAndReleasesWithoutArchiveAreIgnored() throws {
        let releases = try Releases.parse(Data(Self.json.utf8))
        #expect(releases.map(\.version.description) == ["0.3.1", "0.3.0"])
        #expect(releases.first?.notes == "Corrections.")
        #expect(releases.first?.archiveURL.absoluteString == "https://github.com/paulmailhes/polhub/releases/download/v0.3.1/Polhub.zip")
    }

    /// 20/11 : Polhub devient hub-board. La 0.57.0 trouve la 0.57.1 (Polhub.zip, dépôt polhub) ; la 0.57.1 trouve la
    /// 0.58.0 (hub-board.zip, dépôt hub-board) ; une archive d'un autre dépôt n'est jamais prise.
    @Test func bothNamesOfReleaseAreFound() throws {
        let json = """
        [
          {"tag_name": "v0.58.0", "draft": false, "prerelease": false, "body": "Nouveau nom.", "published_at": "2026-11-21T09:00:00Z",
           "assets": [{"name": "hub-board.zip", "browser_download_url": "https://github.com/paulmailhes/hub-board/releases/download/v0.58.0/hub-board.zip"}]},
          {"tag_name": "v0.57.1", "draft": false, "prerelease": false, "body": "Passerelle.", "published_at": "2026-11-20T19:00:00Z",
           "assets": [{"name": "Polhub.zip", "browser_download_url": "https://github.com/paulmailhes/polhub/releases/download/v0.57.1/Polhub.zip"}]},
          {"tag_name": "v0.59.0", "draft": false, "prerelease": false, "body": "Ailleurs.", "published_at": "2026-11-22T09:00:00Z",
           "assets": [{"name": "hub-board.zip", "browser_download_url": "https://github.com/paulmailhes/autre/releases/download/v0.59.0/hub-board.zip"}]}
        ]
        """
        let releases = try Releases.parse(Data(json.utf8))
        #expect(releases.map(\.version.description) == ["0.58.0", "0.57.1"])
        #expect(releases.first?.archiveURL.absoluteString == "https://github.com/paulmailhes/hub-board/releases/download/v0.58.0/hub-board.zip")
        #expect(Releases.archiveNames == ["hub-board.zip", "Polhub.zip"])
    }

    /// Before the repository is renamed, the new address does not answer: the old one does.
    @Test func theOldRepositoryAnswersWhenTheNewOneDoesNot() async throws {
        let asked = Asked()
        let data = try await Releases.fetchFirst(Releases.listURLs) { url in
            await asked.add(url)
            return url == Releases.listURLs[0] ? (Data(), 404) : (Data("[]".utf8), 200)
        }
        #expect(String(decoding: data, as: UTF8.self) == "[]")
        #expect(await asked.urls == Releases.listURLs)
        #expect(Releases.listURLs.map(\.absoluteString) == ["https://api.github.com/repos/paulmailhes/hub-board/releases?per_page=20",
                                                           "https://api.github.com/repos/paulmailhes/polhub/releases?per_page=20"])
    }

    actor Asked {
        var urls: [URL] = []
        func add(_ url: URL) { urls.append(url) }
    }

    @Test func onlyNewerReleasesNewestFirst() throws {
        let releases = try Releases.parse(Data(Self.json.utf8))
        #expect(Releases.newer(than: SemanticVersion("0.3.0")!, in: releases).map(\.version.description) == ["0.3.1"])
        #expect(Releases.newer(than: SemanticVersion("0.3.1")!, in: releases).isEmpty)
        #expect(Releases.newer(than: SemanticVersion("0.2.0")!, in: releases.reversed()).map(\.version.description) == ["0.3.1", "0.3.0"])
    }
}
