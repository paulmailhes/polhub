import CloudKit
import Foundation

/// What changed in the copy since the last look: the copies written, the keys taken away, where to look next time.
public struct CloudChanges: Equatable, Sendable {
    public var copies: [CloudCopy]
    public var deleted: [String]
    public var token: Data?
    public var more: Bool

    public init(copies: [CloudCopy], deleted: [String], token: Data?, more: Bool) {
        self.copies = copies
        self.deleted = deleted
        self.token = token
        self.more = more
    }
}

/// The copy in iCloud, as the Mac writes it and the iPhone reads it; the tests give their own.
public protocol CloudDrive: Sendable {
    /// Whether this device is signed in to iCloud.
    func available() async -> Bool
    /// The copies saved; those refused, with why (a schema not yet in production refuses a record, not the call).
    func save(_ copies: [CloudCopy]) async throws -> [String: String]
    func delete(_ keys: [String]) async throws
    func changes(since token: Data?) async throws -> CloudChanges
}

/// The user's private iCloud database, in the zone `Polhub` of the container shared by the Mac and the iPhone.
public final class ICloudDrive: CloudDrive, @unchecked Sendable {
    let container: CKContainer
    private let lock = NSLock()
    private var zoneReady = false

    public init(identifier: String = CloudRecords.container) {
        container = CKContainer(identifier: identifier)
    }

    var database: CKDatabase { container.privateCloudDatabase }

    public func available() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    func ensureZone() async throws {
        guard !lock.withLock({ zoneReady }) else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: CloudRecords.zoneID)], deleting: [])
        lock.withLock { zoneReady = true }
    }

    public func save(_ copies: [CloudCopy]) async throws -> [String: String] {
        guard !copies.isEmpty else { return [:] }
        try await ensureZone()
        let folder = FileManager.default.temporaryDirectory.appending(path: "polhub-icloud-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var refused: [String: String] = [:]
        // CloudKit takes 400 records by operation at most.
        for start in stride(from: 0, to: copies.count, by: 200) {
            let records = try copies[start..<min(start + 200, copies.count)].map { try CloudRecords.record($0, folder: folder) }
            let (saved, _) = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            for (id, result) in saved {
                if case .failure(let error) = result { refused[id.recordName] = error.localizedDescription }
            }
        }
        return refused
    }

    public func delete(_ keys: [String]) async throws {
        guard !keys.isEmpty else { return }
        try await ensureZone()
        for start in stride(from: 0, to: keys.count, by: 200) {
            let ids = keys[start..<min(start + 200, keys.count)].map { CKRecord.ID(recordName: $0, zoneID: CloudRecords.zoneID) }
            _ = try await database.modifyRecords(saving: [], deleting: ids, savePolicy: .allKeys, atomically: false)
        }
    }

    public func changes(since token: Data?) async throws -> CloudChanges {
        let since = token.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        do {
            let result = try await database.recordZoneChanges(inZoneWith: CloudRecords.zoneID, since: since)
            var copies: [CloudCopy] = []
            for (_, item) in result.modificationResultsByID {
                if case .success(let modification) = item, let copy = try? CloudRecords.copy(modification.record) { copies.append(copy) }
            }
            let next = try? NSKeyedArchiver.archivedData(withRootObject: result.changeToken, requiringSecureCoding: true)
            return CloudChanges(copies: copies, deleted: result.deletions.map(\.recordID.recordName), token: next, more: result.moreComing)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // The Mac has written nothing yet.
            return CloudChanges(copies: [], deleted: [], token: nil, more: false)
        } catch let error as CKError where error.code == .changeTokenExpired && token != nil {
            return try await changes(since: nil)
        }
    }
}
