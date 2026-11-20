import CloudKit
import Foundation
import PolhubLink
import Testing
@testable import PolhubCloud

/// The copy in iCloud (20/11): an answer of the Mac, under the key the iPhone already keeps it by; its content in the
/// fields iCloud encrypts end to end, or in a file when it is large. Every content here is invented.
@Suite struct CloudRecordTests {
    @Test func theKeyIsThePathAndTheSortedQuery() {
        #expect(LinkAPI.key(LinkAPI.Path.projects) == "/v1/projects")
        #expect(LinkAPI.key(LinkAPI.Path.events, query: ["du": "2026-11-20", "au": "2026-11-22"]) == LinkAPI.Path.events + "-au-2026-11-22-du-2026-11-20")
    }

    @Test func aSmallCopyIsEncryptedInTheRecord() throws {
        let copy = CloudCopy(key: "/v1/project-id-A", data: Data(#"{"nom":"Site vitrine"}"#.utf8), date: Date(timeIntervalSince1970: 1_795_000_000))
        let record = try CloudRecords.record(copy)
        #expect(record.recordID.recordName == "/v1/project-id-A" && record.recordType == "Copie")
        #expect(record.recordID.zoneID.zoneName == "Polhub")
        #expect(record.encryptedValues["contenu"] as? Data == copy.data)
        #expect(record["fichier"] == nil && record["contenu"] == nil)
        #expect(try CloudRecords.copy(record) == copy)
    }

    @Test func aLargeCopyGoesInAFile() throws {
        let data = Data(repeating: 0x41, count: CloudRecords.inlineLimit + 1)
        let copy = CloudCopy(key: "/v1/meeting-id-B", data: data, date: Date(timeIntervalSince1970: 1_795_000_000))
        let record = try CloudRecords.record(copy)
        #expect(record.encryptedValues["contenu"] == nil)
        let asset = try #require(record["fichier"] as? CKAsset)
        #expect(asset.fileURL.map { (try? Data(contentsOf: $0)) == data } == true)
        #expect(try CloudRecords.copy(record) == copy)
    }

    @Test func aRecordOfAnotherKindIsNoCopy() throws {
        let other = CKRecord(recordType: "Demande", recordID: CKRecord.ID(recordName: "x", zoneID: CloudRecords.zoneID))
        #expect(try CloudRecords.copy(other) == nil)
    }
}
