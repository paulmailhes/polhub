import Foundation
import Observation
import PolhubLink
import Security
import SwiftUI

/// The iPhone's link to its Mac (20/11): the address and the key, kept in the Keychain; the last answers, kept on the
/// iPhone. In the demonstration mode (`-demo`), made-up answers and nothing leaves the iPhone.
@MainActor @Observable
final class PhoneSession {
    private(set) var connection: LinkConnection?
    /// The Mac's last word about itself.
    private(set) var status: LinkStatus?
    let cache: LinkCache
    let demo: Bool

    init(demo: Bool = ProcessInfo.processInfo.arguments.contains("-demo")) {
        self.demo = demo
        cache = .standard
        connection = demo ? LinkConnection(address: URL(string: "https://mac.exemple.ts.net:8443")!, token: "demo") : Keychain.load()
    }

    var client: LinkClient? { connection.map { LinkClient(connection: $0) } }

    /// The link of the QR code: kept if the Mac answers with it; else what went wrong.
    func pair(with url: URL) async -> String? {
        guard let pairing = LinkAPI.pairing(from: url) else { return "Ce code n'est pas celui de Polhub sur le Mac." }
        let candidate = LinkConnection(address: pairing.address, token: pairing.token)
        do throws(LinkFailure) {
            status = try await LinkClient(connection: candidate).get(LinkStatus.self, LinkAPI.Path.status)
            Keychain.save(candidate)
            connection = candidate
            return nil
        } catch {
            return error.message
        }
    }

    func unpair() {
        Keychain.delete()
        cache.clear()
        connection = nil
        status = nil
    }

    /// The Mac's answer, or its last copy; demo answers in the demonstration mode.
    func fetch<Value: Decodable & Sendable>(_ type: Value.Type, _ path: String, query: [String: String] = [:]) async throws(LinkFailure) -> Fetched<Value> {
        if demo {
            guard let data = LinkDemo.answer(path, query: query), let value = try? LinkAPI.decoder.decode(type, from: data) else {
                throw .refused("Rien à montrer dans la démonstration.")
            }
            return Fetched(value: value, keptAt: nil)
        }
        guard let client else { throw .notPaired("Relie d'abord cet iPhone à ton Mac.") }
        do {
            return try await client.fetch(type, path, query: query, cache: cache)
        } catch .notPaired(let message) {
            // The Mac forgot this iPhone: it pairs again from the start.
            unpair()
            throw .notPaired(message)
        }
    }

    /// A file of a message, written where Quick Look reads it.
    func file(message: String, part: String, name: String) async throws(LinkFailure) -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pieces-jointes", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name.replacingOccurrences(of: "/", with: "-"))
        if demo {
            try? Data("Démonstration".utf8).write(to: url)
            return url
        }
        guard let client else { throw .notPaired("Relie d'abord cet iPhone à ton Mac.") }
        let data = try await client.data(LinkAPI.Path.file, query: ["message": message, "piece": part])
        do { try data.write(to: url, options: .completeFileProtection) } catch { throw .refused("La pièce jointe n'a pas pu être enregistrée sur l'iPhone.") }
        return url
    }

    func refreshStatus() async {
        status = try? await fetch(LinkStatus.self, LinkAPI.Path.status).value
    }

    // MARK: - Writing (lot 3, 20/11)

    /// The mail leaving from the Mac, while it can be called back: the pill at the bottom.
    private(set) var sending: LinkSending?
    private var watching: Task<Void, Never>?

    /// A POST to the Mac; in the demonstration, nothing leaves.
    func post<Value: Decodable & Sendable>(_ type: Value.Type, _ path: String, body: some Encodable & Sendable) async throws(LinkFailure) -> Value {
        if demo {
            guard let data = LinkDemo.answer(path, query: [:]), let value = try? LinkAPI.decoder.decode(type, from: data) else {
                throw .refused("La démonstration n'envoie rien.")
            }
            return value
        }
        guard let client else { throw .notPaired("Relie d'abord cet iPhone à ton Mac.") }
        return try await client.post(type, path, body: body)
    }

    /// A reply or a new mail, handed to the Mac, which sends it after its delay; nil when it left, else why not.
    func send(reply: LinkReply? = nil, mail: LinkNewMail? = nil) async -> String? {
        do throws(LinkFailure) {
            let leaving = if let reply { try await post(LinkSending.self, LinkAPI.Path.reply, body: reply) }
                          else { try await post(LinkSending.self, LinkAPI.Path.newMail, body: mail) }
            sending = leaving
            watch()
            return nil
        } catch {
            return error.message
        }
    }

    /// « Annuler »: the mail stays a draft on the Mac.
    func cancelSending() async {
        guard let sending else { return }
        _ = try? await post(LinkSending?.self, LinkAPI.Path.cancel, body: LinkCancel(draftID: sending.draftID))
        self.sending = nil
    }

    /// The pill follows the Mac until the mail left.
    private func watch() {
        watching?.cancel()
        watching = Task { [weak self] in
            while let self, self.sending != nil, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !self.demo else {
                    if let at = self.sending?.at, at < Date() { self.sending = nil }
                    continue
                }
                if let client = self.client {
                    self.sending = try? await client.get(LinkSending?.self, LinkAPI.Path.sending)
                }
            }
        }
    }
}

/// The address and the key of the Mac, in the iPhone's Keychain, never synced elsewhere.
enum Keychain {
    static let service = "fr.paulmailhes.polhub.ios"
    static let account = "mac"

    static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func save(_ connection: LinkConnection) {
        delete()
        guard let data = try? JSONEncoder().encode(connection) else { return }
        var item = base()
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> LinkConnection? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LinkConnection.self, from: data)
    }

    static func delete() {
        SecItemDelete(base() as CFDictionary)
    }
}

/// Polhub's ink: near black in light, near white in dark (the Mac's accent, 19/11).
extension Color {
    static let ink = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
                                                                    : UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1) })

    /// `#RRGGBB`.
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
