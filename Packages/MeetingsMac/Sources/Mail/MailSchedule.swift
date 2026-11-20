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
    /// Gmail's copy of the draft as Polhub last gave it (its draft, its message), kept here and not only in the base:
    /// a row whose ids were cleared or changed never skips the check of what the phone did (security review).
    public var gmailDraftID: String?
    public var gmailMessageID: String?
    /// The first time Polhub tried to send it: late from the start (the Mac asleep, Polhub closed), or late because
    /// Gmail did not answer at its time.
    public var firstTriedAt: Date?

    public var id: String { draftID }

    public init(draftID: String, account: String, sendAt: Date, fingerprint: String, subject: String, threadKey: String?,
                state: State = .waiting, lastError: String? = nil, createdAt: Date, gmailDraftID: String? = nil, gmailMessageID: String? = nil,
                firstTriedAt: Date? = nil) {
        self.draftID = draftID
        self.account = account.lowercased()
        self.sendAt = sendAt
        self.fingerprint = fingerprint
        self.subject = subject
        self.threadKey = threadKey
        self.state = state
        self.lastError = lastError
        self.createdAt = createdAt
        self.gmailDraftID = gmailDraftID
        self.gmailMessageID = gmailMessageID
        self.firstTriedAt = firstTriedAt
    }

    /// Late because Gmail or the network did not answer at its time, rather than the Mac asleep or Polhub closed:
    /// Polhub first tried within five minutes of it.
    public var gmailWasLate: Bool {
        firstTriedAt.map { $0.timeIntervalSince(sendAt) <= 5 * 60 } ?? false
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
    /// The item under the vault's name was not Polhub's (any program could read it): its list was set aside, never
    /// read, and Polhub's own, empty, took its place.
    case foreign

    public var description: String {
        switch self {
        case .unreadable(let status): "le Trousseau ne donne pas les envois programmés (\(status))"
        case .unwritable(let status): "le Trousseau n'a pas pris les envois programmés (\(status))"
        case .foreign: "une liste d'envois programmés que Polhub n'avait pas écrite était dans le Trousseau"
        }
    }
}

/// The vault's error in Paul's words, for `Words.problem` (lot 10, 20/11): the Keychain's code stays in `description`.
extension ScheduleVaultError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .unreadable: "le Trousseau ne donne pas les envois programmés"
        case .unwritable: "le Trousseau n'a pas pris les envois programmés"
        case .foreign: "une liste d'envois programmés inconnue était dans le Trousseau"
        }
    }
}

/// The vault's item as the Keychain gives it.
public enum VaultItem: Sendable, Equatable {
    /// Readable by Polhub alone, as Polhub makes it: its list.
    case kept(Data)
    /// Any program may read it without asking (`security add-generic-password -A`). Polhub never makes such an
    /// item: another program put it there, and its list is not even read.
    case openToAll
}

/// The one Keychain item that holds the list (security review of wave B).
public protocol VaultKeychain: Sendable {
    /// `nil` when there is none; throws when the Keychain does not answer (locked, refused).
    func read() throws -> VaultItem?
    /// Writes over the item in place; `false` when there is none.
    func update(_ data: Data) throws -> Bool
    /// Makes the item, readable by Polhub alone.
    func add(_ data: Data) throws
    func delete() throws
}

/// The login Keychain and it only: a keychain another program puts ahead of it in the search list is never read.
/// The item is made by Polhub (its access list trusts Polhub alone, as the Google tokens).
public struct LoginKeychainItem: VaultKeychain {
    let service: String
    let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private func login() throws -> SecKeychain {
        let folder = URL.homeDirectory.appending(path: "Library/Keychains", directoryHint: .isDirectory)
        guard let path = ["login.keychain-db", "login.keychain"].map({ folder.appending(path: $0).path(percentEncoded: false) })
            .first(where: { FileManager.default.fileExists(atPath: $0) }) else { throw ScheduleVaultError.unreadable(errSecNoSuchKeychain) }
        var keychain: SecKeychain?
        let status = SecKeychainOpen(path, &keychain)
        guard status == errSecSuccess, let keychain else { throw ScheduleVaultError.unreadable(status) }
        return keychain
    }

    private func query(_ keychain: SecKeychain) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecMatchSearchList as String: [keychain]]
    }

    public func read() throws -> VaultItem? {
        let keychain = try login()
        var find = query(keychain)
        find[kSecReturnRef as String] = true
        find[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: AnyObject?
        let status = SecItemCopyMatching(find as CFDictionary, &found)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let found, CFGetTypeID(found) == SecKeychainItemGetTypeID() else { throw ScheduleVaultError.unreadable(status) }
        // Who may read it, before reading it.
        if try Self.openToAll(found as! SecKeychainItem) { return .openToAll }
        var read = query(keychain)
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let readStatus = SecItemCopyMatching(read as CFDictionary, &result)
        guard readStatus == errSecSuccess, let data = result as? Data else { throw ScheduleVaultError.unreadable(readStatus) }
        return .kept(data)
    }

    /// An entry of the access list that lets any program read the secret (decrypt, export it in clear, or anything)
    /// with no list of programs at all. The entries that only let a program write (« encrypt ») or that say who
    /// made the item (partition, integrity) have no list either: they are left out.
    static func openToAll(_ item: SecKeychainItem) throws -> Bool {
        var access: SecAccess?
        var status = SecKeychainItemCopyAccess(item, &access)
        guard status == errSecSuccess, let access else { throw ScheduleVaultError.unreadable(status) }
        var list: CFArray?
        status = SecAccessCopyACLList(access, &list)
        guard status == errSecSuccess, let entries = list as? [SecACL] else { throw ScheduleVaultError.unreadable(status) }
        let reading = Set([kSecACLAuthorizationAny, kSecACLAuthorizationDecrypt, kSecACLAuthorizationExportClear].map { $0 as String })
        for entry in entries {
            let tags = (SecACLCopyAuthorizations(entry) as? [String]) ?? []
            guard tags.contains(where: reading.contains) else { continue }
            var programs: CFArray?
            var description: CFString?
            var prompt = SecKeychainPromptSelector()
            status = SecACLCopyContents(entry, &programs, &description, &prompt)
            guard status == errSecSuccess else { throw ScheduleVaultError.unreadable(status) }
            if programs == nil { return true }
        }
        return false
    }

    public func update(_ data: Data) throws -> Bool {
        let status = SecItemUpdate(query(try login()) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw ScheduleVaultError.unwritable(status) }
        return true
    }

    public func add(_ data: Data) throws {
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                   kSecUseKeychain as String: try login(), kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ScheduleVaultError.unwritable(status) }
    }

    public func delete() throws {
        let status = SecItemDelete(query(try login()) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ScheduleVaultError.unwritable(status) }
    }
}

/// The login Keychain: one item for the whole list, readable only by Polhub (as the Google tokens). One account
/// per flavor: the development build never shares, and the engine never calls it there anyway.
///
/// Any program running as Paul may make an item under this name while there is none (`security
/// add-generic-password`), or put a keychain ahead of the login one: the item is looked for in the login keychain
/// only, and one that any program could read is never Polhub's, so its list is never adopted (security review of
/// wave B). What only a data-protection keychain with Polhub's own access group would close (an item made by
/// another program for Polhub alone) waits for a provisioning profile (to measure on Paul's Mac).
public struct KeychainScheduleVault: ScheduleVault {
    public static let service = "fr.paulmailhes.polhub.envois-programmes"
    let keychain: any VaultKeychain

    public init(flavor: AppFlavor = .current) {
        self.init(keychain: LoginKeychainItem(service: Self.service, account: flavor.rawValue))
    }

    public init(keychain: any VaultKeychain) {
        self.keychain = keychain
    }

    public func load() throws -> [ScheduledSend] {
        switch try keychain.read() {
        case nil:
            // Made at once, by Polhub: no other program finds the place free to put a list of its own there.
            try keychain.add(try JSONEncoder().encode([ScheduledSend]()))
            return []
        case .openToAll?:
            // Another program's: never read, never sent. Polhub's own, empty, takes its place, and Paul is told.
            try keychain.delete()
            try keychain.add(try JSONEncoder().encode([ScheduledSend]()))
            throw ScheduleVaultError.foreign
        case .kept(let data)?:
            return try JSONDecoder().decode([ScheduledSend].self, from: data)
        }
    }

    public func save(_ all: [ScheduledSend]) throws {
        let data = try JSONEncoder().encode(all)
        // Changed in place: there is never a moment without the item.
        if try !keychain.update(data) { try keychain.add(data) }
    }
}

/// A vault in memory: the tests, and every library that does not speak to the real Gmail (nothing survives a
/// launch). It counts what it is asked, and can be made to fail.
public final class MemoryScheduleVault: ScheduleVault, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [ScheduledSend]
    private var loadCount = 0
    private var saveCount = 0
    private var saveAttempts = 0
    private var failingLoads = 0
    private var failingSaves = 0

    public init(_ entries: [ScheduledSend] = []) {
        self.entries = entries
    }

    public var all: [ScheduledSend] { lock.withLock { entries } }
    public var loads: Int { lock.withLock { loadCount } }
    public var saves: Int { lock.withLock { saveCount } }
    /// Every save asked, refused ones too.
    public var attempts: Int { lock.withLock { saveAttempts } }
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
            saveAttempts += 1
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
    /// The Keychain held a list Polhub never wrote: set aside, nothing of it left (security review of wave B).
    case setAside
}

/// Why a programmed send stopped for good.
public enum ScheduleStop: Error, Sendable, Equatable, CustomStringConvertible {
    /// The mail built now is not the one programmed: the draft, its files or the signature changed.
    case changed
    /// Gmail's copy was sent, deleted or changed elsewhere (the phone).
    case conflict(MailDraftRow.Conflict)
    /// Gmail's copy is in the trash (the conversation deleted on the phone).
    case trashed
    /// The mailbox no longer lets Polhub read and send its mails.
    case noAccess
    /// The draft is gone.
    case vanished
    /// Gmail refused it.
    case refused(String)

    public var description: String {
        switch self {
        case .changed: "le brouillon a changé depuis que tu l'as programmé"
        case .conflict(.absent): "le brouillon n'est plus dans Gmail : envoyé ou supprimé ailleurs"
        case .conflict(.modifie): "le brouillon a été modifié dans Gmail, sur un autre appareil"
        case .trashed: "il a été mis à la corbeille dans Gmail"
        case .noAccess: "Polhub n'a plus accès aux mails de cette boîte"
        case .vanished: "le brouillon n'existe plus"
        case .refused(let reason): "Gmail l'a refusé (\(reason))"
        }
    }
}

/// Why a send stopped, in Paul's words, for `Words.problem` (lot 10, 20/11): one « : » in a sentence, the rest after it.
extension ScheduleStop: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .conflict(.absent): "le brouillon n'est plus dans Gmail"
        default: description
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .conflict(.absent): "Il a peut-être été envoyé ou supprimé ailleurs."
        case .noAccess: "Autorise les mails dans Réglages › Comptes Google."
        default: nil
        }
    }
}

/// Paul's demand that the engine refuses.
public enum ScheduleError: Error, Equatable, CustomStringConvertible {
    /// At least a minute from now.
    case tooSoon
    /// On its way to Gmail: too late to call it back or send it again.
    case leaving
    /// « Envoyer maintenant » on a mail no longer programmed (sent, stopped, cancelled meanwhile).
    case notScheduled

    public var description: String {
        switch self {
        case .tooSoon: "choisis une heure au moins une minute plus tard"
        case .leaving: "le mail est déjà en route"
        case .notScheduled: "il n'est plus programmé : regarde dans Brouillons"
        }
    }
}

/// Paul's demand refused, in his words, for `Words.problem` (lot 10, 20/11): the reason, then what to do.
extension ScheduleError: LocalizedError {
    public var failureReason: String? {
        switch self {
        case .tooSoon: "l'heure choisie est trop proche"
        case .leaving: "le mail est déjà en route"
        case .notScheduled: "il n'est plus programmé"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .tooSoon: "Choisis une heure au moins une minute plus tard."
        case .leaving: "Regarde dans Envoyés."
        case .notScheduled: "Regarde dans Brouillons."
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
