import CloudKit
import Foundation
import PolhubLink

/// An answer of the Mac, copied into the user's iCloud (20/11): what the iPhone shows when the Mac does not answer.
public struct CloudCopy: Equatable, Sendable {
    /// `LinkAPI.key`: the path and the query, as the iPhone keeps it.
    public var key: String
    public var data: Data
    /// When the Mac made it.
    public var date: Date

    public init(key: String, data: Data, date: Date) {
        self.key = key
        self.data = data
        self.date = date
    }
}

/// The two kinds of records of Polhub's container, and nothing more: a schema in production changes only by Apple's
/// console, so their content is JSON, which changes with the app (`Copie`, and later `Demande`).
public enum CloudRecords {
    public static let container = "iCloud.fr.paulmailhes.polhub"
    public static let zoneID = CKRecordZone.ID(zoneName: "Polhub", ownerName: CKCurrentUserDefaultName)
    public static let copyType = "Copie"
    /// Above this, the content goes in a file: a record holds 1 MB at most.
    public static let inlineLimit = 700_000

    enum Field {
        static let path = "chemin"
        static let content = "contenu"
        static let file = "fichier"
        static let date = "date"
    }

    /// The record of a copy: its content in the fields iCloud encrypts end to end, or in a file when it is large.
    public static func record(_ copy: CloudCopy, folder: URL = FileManager.default.temporaryDirectory) throws -> CKRecord {
        let record = CKRecord(recordType: copyType, recordID: CKRecord.ID(recordName: copy.key, zoneID: zoneID))
        record[Field.path] = copy.key
        record[Field.date] = copy.date
        if copy.data.count > inlineLimit {
            let file = folder.appending(path: "polhub-copie-\(UUID().uuidString).json")
            try copy.data.write(to: file, options: .atomic)
            record[Field.file] = CKAsset(fileURL: file)
        } else {
            record.encryptedValues[Field.content] = copy.data
        }
        return record
    }

    /// The copy a record holds; none for a record of another kind.
    public static func copy(_ record: CKRecord) throws -> CloudCopy? {
        guard record.recordType == copyType else { return nil }
        let data: Data
        if let content = record.encryptedValues[Field.content] as? Data {
            data = content
        } else if let url = (record[Field.file] as? CKAsset)?.fileURL {
            data = try Data(contentsOf: url)
        } else {
            return nil
        }
        return CloudCopy(key: record[Field.path] as? String ?? record.recordID.recordName, data: data,
                         date: record[Field.date] as? Date ?? record.modificationDate ?? .distantPast)
    }
}
