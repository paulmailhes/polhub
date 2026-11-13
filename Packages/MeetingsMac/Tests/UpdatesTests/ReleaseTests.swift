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
       "assets": [{"name": "Transcriptor.zip", "browser_download_url": "https://github.com/x/y/releases/download/v0.3.2/Transcriptor.zip"}]},
      {"tag_name": "v0.3.1", "draft": false, "prerelease": false, "body": "Corrections.", "published_at": "2026-11-14T09:00:00Z",
       "assets": [{"name": "Transcriptor.zip", "browser_download_url": "https://github.com/x/y/releases/download/v0.3.1/Transcriptor.zip"}]},
      {"tag_name": "v0.4.0-beta", "draft": false, "prerelease": true, "body": "", "published_at": "2026-11-14T10:00:00Z",
       "assets": [{"name": "Transcriptor.zip", "browser_download_url": "https://github.com/x/y/releases/download/v0.4.0-beta/Transcriptor.zip"}]},
      {"tag_name": "v0.3.3", "draft": false, "prerelease": false, "body": "Sans archive.", "published_at": "2026-11-14T11:00:00Z",
       "assets": [{"name": "autre.zip", "browser_download_url": "https://github.com/x/y/releases/download/v0.3.3/autre.zip"}]},
      {"tag_name": "v0.3.0", "draft": false, "prerelease": false, "body": "Première version.", "published_at": "2026-11-13T18:00:00Z",
       "assets": [{"name": "Transcriptor.zip", "browser_download_url": "https://github.com/x/y/releases/download/v0.3.0/Transcriptor.zip"}]}
    ]
    """

    @Test func draftsPrereleasesAndReleasesWithoutArchiveAreIgnored() throws {
        let releases = try Releases.parse(Data(Self.json.utf8))
        #expect(releases.map(\.version.description) == ["0.3.1", "0.3.0"])
        #expect(releases.first?.notes == "Corrections.")
        #expect(releases.first?.archiveURL.absoluteString == "https://github.com/x/y/releases/download/v0.3.1/Transcriptor.zip")
    }

    @Test func onlyNewerReleasesNewestFirst() throws {
        let releases = try Releases.parse(Data(Self.json.utf8))
        #expect(Releases.newer(than: SemanticVersion("0.3.0")!, in: releases).map(\.version.description) == ["0.3.1"])
        #expect(Releases.newer(than: SemanticVersion("0.3.1")!, in: releases).isEmpty)
        #expect(Releases.newer(than: SemanticVersion("0.2.0")!, in: releases.reversed()).map(\.version.description) == ["0.3.1", "0.3.0"])
    }
}
