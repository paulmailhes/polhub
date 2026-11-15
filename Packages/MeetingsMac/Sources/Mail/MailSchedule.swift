import CryptoKit
import Domain
import Foundation
import MailFormat
import Persistence
import Security

/// A mail Paul programmed (« Programmer l'envoi », wave B, 15/11). The Gmail API has no send at a given time:
/// Polhub keeps the mail and sends it itself. The entry lives in the Keychain, never in the base: a row of the
/// base, a preference or a restored backup can never ask for a send. It holds the fingerprint of exactly what
/// leaves; at the time, the mail is built again, and any difference stops it.
public struct ScheduledSend: Codable, Sendable, Equatable, Identifiable {
    public enum State: String, Codable, Sendable {
        /// Waits for its time.
        case waiting
        /// Claimed: on its way to Gmail. Found so at a launch, it may have left: never sent again.
        case leaving
        /// More than `MailEngine.lateLimit` late (the Mac asleep, Polhub closed): it waits for Paul.
        case held
    }

    public var draftID: String
    public var account: String
    public var sendAt: Date
    /// SHA-256 of what leaves (`OutgoingMail.fingerprint`).
    public var fingerprint: String
    /// For the notifications, the lines and the banner.
    public var subject: String
    public var threadKey: String?
    public var state: State
    public var lastError: String?
    public var createdAt: Date

    public var id: String { draftID }

    public init(draftID: String, account: String, sendAt: Date, fingerprint: String, subject: String, threadKey: String?,
                state: State = .waiting, lastError: String? = nil, createdAt: Date) {
        self.draftID = draftID
        self.account = account.lowercased()
        self.sendAt = sendAt
        self.fingerprint = fingerprint
        self.subject = subject
        self.threadKey = threadKey
        self.state = state
        self.lastError = lastError
        self.createdAt = createdAt
    }
}

/// Where the programmed sends are kept. Only the app reads and writes it.
public protocol ScheduleVault: Sendable {
    /// Every entry; `[]` only when there is none. A vault that cannot be read throws: it never reads as empty,
    /// or the next save would erase every programmed send.
    func load() throws -> [ScheduledSend]
    func save(_ all: [ScheduledSend]) throws
}

public enum ScheduleVaultError: Error, Equatable, CustomStringConvertible {
    case unreadable(Int32)
    case unwritable(Int32)

    public var description: String {
        switch self {
        case .unreadable(let status): "le Trousseau ne donne pas les envois programmés (\(status))"
        case .unwritable(let status): "le Trousseau n'a pas pris les envois programmés (\(status))"
        }
    }
}

/// The login Keychain: one item for the whole list, readable only by Polhub (as the Google tokens). One account
/// per flavor: the development build never shares, and the engine never calls it there anyway.
public struct KeychainScheduleVault: ScheduleVault {
    public static let service = "fr.paulmailhes.polhub.envois-programmes"
    let account: String

    public init(flavor: AppFlavor = .current) {
        account = flavor.rawValue
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: account]
    }

    public func load() throws -> [ScheduledSend] {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound {
            // Made at once, by Polhub: no other program finds the place free to put a list of its own there.
            try save([])
            return []
        }
        guard status == errSecSuccess, let data = result as? Data else { throw ScheduleVaultError.unreadable(status) }
        return try JSONDecoder().decode([ScheduledSend].self, from: data)
    }

    public func save(_ all: [ScheduledSend]) throws {
        let data = try JSONEncoder().encode(all)
        // Changed in place: there is never a moment without the item.
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw ScheduleVaultError.unwritable(added) }
        } else if status != errSecSuccess {
            throw ScheduleVaultError.unwritable(status)
        }
    }
}

/// A vault in memory: the tests, and every library that does not speak to the real Gmail (nothing survives a
/// launch). It counts what it is asked, and can be made to fail.
public final class MemoryScheduleVault: ScheduleVault, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ScheduledSend]
    private var loadCount = 0
    private var saveCount = 0
    private var failingLoads = 0
    private var failingSaves = 0

    public init(_ entries: [ScheduledSend] = []) {
        self.entries = entries
    }

    public var all: [ScheduledSend] { lock.withLock { entries } }
    public var loads: Int { lock.withLock { loadCount } }
    public var saves: Int { lock.withLock { saveCount } }
    /// The next `count` loads fail, as a locked Keychain.
    public func failLoads(_ count: Int) { lock.withLock { failingLoads = count } }
    public func failSaves(_ count: Int) { lock.withLock { failingSaves = count } }

    public func load() throws -> [ScheduledSend] {
        try lock.withLock {
            loadCount += 1
            if failingLoads > 0 {
                failingLoads -= 1
                throw ScheduleVaultError.unreadable(-25308)
            }
            return entries
        }
    }

    public func save(_ all: [ScheduledSend]) throws {
        try lock.withLock {
            if failingSaves > 0 {
                failingSaves -= 1
                throw ScheduleVaultError.unwritable(-25308)
            }
            saveCount += 1
            entries = all
        }
    }
}

/// What became of a programmed send: told to Paul (a line, a notification).
public enum ScheduleOutcome: Sendable, Equatable {
    /// It left, `at` (late when well after its time).
    case sent(ScheduledSend, at: Date)
    /// Too late to leave on its own: it waits for Paul in « Programmés ».
    case held(ScheduledSend)
    /// It did not leave, and will not: the draft stays in Brouillons.
    case stopped(ScheduledSend, ScheduleStop)
    /// Polhub stopped while it was leaving: it may have left. Never sent again.
    case maybeSent(ScheduledSend)
}

/// Why a programmed send stopped for good.
public enum ScheduleStop: Error, Sendable, Equatable, CustomStringConvertible {
    /// The mail built now is not the one programmed: the draft, its files or the signature changed.
    case changed
    /// Gmail's copy was sent, deleted or changed elsewhere (the phone).
    case conflict(MailDraftRow.Conflict)
    /// The draft is gone.
    case vanished
    /// Gmail refused it.
    case refused(String)

    public var description: String {
        switch self {
        case .changed: "le brouillon a changé depuis que tu l'as programmé"
        case .conflict(.absent): "le brouillon n'est plus dans Gmail : envoyé ou supprimé ailleurs"
        case .conflict(.modifie): "le brouillon a été modifié dans Gmail, sur un autre appareil"
        case .vanished: "le brouillon n'existe plus"
        case .refused(let reason): "Gmail l'a refusé (\(reason))"
        }
    }
}

/// Paul's demand that the engine refuses.
public enum ScheduleError: Error, Equatable, CustomStringConvertible {
    /// At least a minute from now.
    case tooSoon
    /// On its way to Gmail: too late to call it back or send it again.
    case leaving

    public var description: String {
        switch self {
        case .tooSoon: "choisis une heure au moins une minute plus tard"
        case .leaving: "le mail est déjà en route"
        }
    }
}

extension OutgoingMail {
    /// SHA-256 of exactly what leaves: the thread, who from, who to, the subject, the text and the HTML (Paul's
    /// words, the signature, the quote), the thread's headers, and each file's name, type and bytes. The date is
    /// left out: it is the moment it leaves. Each field is prefixed with its length: « ab » + « c » is not
    /// « a » + « bc ».
    public func fingerprint(threadKey: String?) -> String {
        var hasher = SHA256()
        func add(_ text: String?) {
            guard let text else {
                hasher.update(data: Data([0]))
                return
            }
            let bytes = Data(text.utf8)
            var length = UInt64(bytes.count).bigEndian
            hasher.update(data: Data([1]))
            withUnsafeBytes(of: &length) { hasher.update(bufferPointer: $0) }
            hasher.update(data: bytes)
        }
        func add(_ people: [MailAddress]) {
            add(String(people.count))
            for person in people {
                add(person.name)
                add(person.email)
            }
        }
        add("polhub/envoi-programme/1")
        add(threadKey)
        add(from.name)
        add(from.email)
        add(to)
        add(cc)
        add(bcc)
        add(subject)
        add(text)
        add(html)
        add(inReplyTo)
        add(references)
        add(String(files.count))
        for file in files {
            add(file.filename)
            add(file.mimeType)
            add(SHA256.hash(data: file.data).map { String(format: "%02x", $0) }.joined())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
