import Foundation
import Testing
@testable import HubLink

/// The iPhone's copy (20/11), fed by the Mac when it answers and by iCloud when it does not: the most recent wins, and
/// its date is the Mac's.
@Suite struct LinkCacheTests {
    func cache() -> LinkCache {
        LinkCache(folder: FileManager.default.temporaryDirectory.appending(path: "copie-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func aCopyKeepsTheDateItWasMade() throws {
        let cache = cache()
        defer { cache.clear() }
        let made = Date(timeIntervalSince1970: 1_795_000_000)
        cache.store(Data("A".utf8), for: "/v1/projects", at: made)
        let kept = try #require(cache.load("/v1/projects"))
        #expect(kept.data == Data("A".utf8) && abs(kept.keptAt.timeIntervalSince(made)) < 1)
    }

    @Test func onlyAMoreRecentCopyReplacesTheOneKept() throws {
        let cache = cache()
        defer { cache.clear() }
        let earlier = Date(timeIntervalSince1970: 1_795_000_000)
        cache.store(Data("vu en direct".utf8), for: "/v1/projects", at: earlier.addingTimeInterval(600))
        #expect(cache.storeIfNewer(Data("copie plus ancienne".utf8), for: "/v1/projects", at: earlier) == false)
        #expect(try #require(cache.load("/v1/projects")).data == Data("vu en direct".utf8))
        #expect(cache.storeIfNewer(Data("copie plus récente".utf8), for: "/v1/projects", at: earlier.addingTimeInterval(1_200)))
        #expect(try #require(cache.load("/v1/projects")).data == Data("copie plus récente".utf8))
        #expect(cache.storeIfNewer(Data("neuve".utf8), for: "/v1/meetings", at: earlier))
    }

    @Test func aCopyTakenAwayGoes() {
        let cache = cache()
        defer { cache.clear() }
        cache.store(Data("A".utf8), for: "/v1/project-id-A")
        cache.remove("/v1/project-id-A")
        #expect(cache.load("/v1/project-id-A") == nil)
    }
}
