import Domain
import Foundation
import Persistence
import PolhubCloud
import PolhubLink
import Testing
@testable import MeetingsUI

/// The copy in iCloud (20/11): the Mac copies what the iPhone shows, the mails apart, so that the iPhone shows it
/// with the Mac off. Every name here is invented.
@MainActor @Suite struct PhoneCloudTests {
    /// iCloud, in memory.
    final class MemoryDrive: CloudDrive, @unchecked Sendable {
        private let lock = NSLock()
        private var copies: [String: CloudCopy] = [:]
        private var batches: [[String]] = []
        var signedIn = true
        var refusing = false

        var stored: [String: CloudCopy] { lock.withLock { copies } }
        var saved: [[String]] { lock.withLock { batches } }

        func put(_ copy: CloudCopy) { lock.withLock { copies[copy.key] = copy } }
        func available() async -> Bool { signedIn }

        func save(_ given: [CloudCopy]) async throws -> [String: String] {
            lock.withLock {
                batches.append(given.map(\.key).sorted())
                if refusing { return Dictionary(uniqueKeysWithValues: given.map { ($0.key, "Cannot create new type Copie in production schema") }) }
                for copy in given { copies[copy.key] = copy }
                return [:]
            }
        }

        func delete(_ keys: [String]) async throws { lock.withLock { for key in keys { copies[key] = nil } } }
        func changes(since token: Data?) async throws -> CloudChanges { CloudChanges(copies: Array(stored.values), deleted: [], token: nil, more: false) }

        private var asked: [CloudRequest] = []
        func ask(_ request: CloudRequest) { lock.withLock { asked.append(request) } }
        func send(_ request: CloudRequest) async throws { ask(request) }
        /// Each request once, as iCloud's changes would give them.
        func requests(since token: Data?) async throws -> CloudRequests {
            lock.withLock {
                let given = asked
                asked = []
                return CloudRequests(requests: given, token: Data("jeton".utf8), more: false)
            }
        }
    }

    struct World {
        let cloud: PhoneCloud
        let drive: MemoryDrive
        let database: AppDatabase
        let defaults: UserDefaults
        let api: PhoneAPI
    }

    func world() throws -> World {
        let database = try AppDatabase.inMemory()
        let defaults = try #require(UserDefaults(suiteName: "icloud-\(UUID().uuidString)"))
        let api = PhoneAPI(devices: PhoneDevices(defaults: defaults), database: database, agenda: nil, mails: nil, appVersion: "0.55.0")
        let drive = MemoryDrive()
        return World(cloud: PhoneCloud(api: api, drive: drive, defaults: defaults), drive: drive, database: database, defaults: defaults, api: api)
    }

    @Test func theMacCopiesWhatTheIPhoneShowsButTheMails() async throws {
        let world = try world()
        let store = ProjectStore(world.database)
        let site = try store.addProject(name: "Site vitrine", status: .priorite2, at: Date())
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let meeting = MeetingRow(createdAt: start, status: .ended, source: .dia, candidateKey: "k", title: "Point hebdo", startedAt: start,
                                 endedAt: start.addingTimeInterval(1_800))
        try MeetingStore(world.database).save(meeting)
        await world.cloud.copy()
        let keys = Set(world.drive.stored.keys)
        for key in [LinkAPI.Path.status, LinkAPI.Path.projects, LinkAPI.key(LinkAPI.Path.project, query: ["id": site.id.uuidString]),
                    LinkAPI.Path.meetings, LinkAPI.key(LinkAPI.Path.meeting, query: ["id": meeting.id.uuidString]), LinkAPI.Path.events] {
            #expect(keys.contains(key), "\(key)")
        }
        #expect(!keys.contains { $0.hasPrefix("/v1/mail") })
        let projects = try LinkAPI.decoder.decode([LinkProject].self, from: try #require(world.drive.stored[LinkAPI.Path.projects]).data)
        #expect(projects.map(\.name) == ["Site vitrine"])
        #expect(world.cloud.lastCopy != nil && world.cloud.problem == nil)
    }

    @Test func anUnchangedAnswerIsNotWrittenAgain() async throws {
        let world = try world()
        let store = ProjectStore(world.database)
        let site = try store.addProject(name: "Site vitrine", status: .priorite2, at: Date())
        await world.cloud.copy()
        await world.cloud.copy()
        #expect(world.drive.saved.count == 1)
        try store.saveAction(ActionRow(projectID: site.id, text: "Envoyer le devis", position: 0, createdAt: Date()))
        await world.cloud.copy()
        #expect(world.drive.saved.last?.contains(LinkAPI.key(LinkAPI.Path.project, query: ["id": site.id.uuidString])) == true)
        #expect(world.drive.saved.last?.contains(LinkAPI.Path.meetings) == false)
    }

    @Test func whatIsGoneFromTheMacIsTakenAwayFromICloud() async throws {
        let world = try world()
        await world.cloud.copy()
        let old = LinkAPI.key(LinkAPI.Path.project, query: ["id": UUID().uuidString])
        world.drive.put(CloudCopy(key: old, data: Data("{}".utf8), date: Date()))
        var hashes = world.defaults.dictionary(forKey: PhoneCloud.hashesKey) as? [String: String] ?? [:]
        hashes[old] = "ancien"
        world.defaults.set(hashes, forKey: PhoneCloud.hashesKey)
        await world.cloud.copy()
        #expect(world.drive.stored[old] == nil)
    }

    /// 20/11: a schema not yet in production refuses each record, not the call; the copy says so and tries again.
    @Test func aRefusedCopyIsSaidAndTriedAgain() async throws {
        let world = try world()
        world.drive.refusing = true
        await world.cloud.copy()
        #expect(world.cloud.problem != nil && world.drive.stored.isEmpty)
        world.drive.refusing = false
        await world.cloud.copy()
        #expect(world.cloud.problem == nil && world.drive.stored[LinkAPI.Path.projects] != nil)
    }

    @Test func withoutICloudNothingIsWrittenAndItIsSaid() async throws {
        let world = try world()
        world.drive.signedIn = false
        await world.cloud.copy()
        #expect(world.drive.saved.isEmpty && world.cloud.problem == PhoneCloud.Texts.signedOut)
    }

    @Test func switchedOffItCopiesNothing() async throws {
        let world = try world()
        world.cloud.enabled = false
        await world.cloud.copy()
        #expect(world.drive.saved.isEmpty)
        #expect(world.defaults.bool(forKey: PhoneCloud.enabledKey) == false)
    }
}
