import CryptoKit
import Foundation

/// An iPhone paired with this Mac (20/11). Only its token's fingerprint is kept: the token itself lives in the
/// iPhone's Keychain, and leaves the Mac once, in the QR code.
public struct PhoneDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    var tokenHash: String
    public var pairedAt: Date
    /// Its last request; nil while the QR code waits to be scanned.
    public var lastSeenAt: Date?
}

/// The iPhones paired with this Mac, in its preferences. A QR code not scanned within ten minutes is forgotten.
public final class PhoneDevices: @unchecked Sendable {
    static let key = "iphone.appareils"
    /// How long a QR code waits to be scanned.
    public static let pairingLifetime: TimeInterval = 10 * 60

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var all: [PhoneDevice] {
        lock.withLock { stored() }
    }

    /// A new token, for a QR code: the device waits for its first request.
    public func pair(name: String = "iPhone", now: Date = Date()) -> (device: PhoneDevice, token: String) {
        let token = Self.newToken()
        let device = PhoneDevice(id: UUID(), name: name, tokenHash: Self.hash(token), pairedAt: now, lastSeenAt: nil)
        lock.withLock {
            var devices = stored().filter { $0.lastSeenAt != nil || now.timeIntervalSince($0.pairedAt) < Self.pairingLifetime }
            devices.append(device)
            save(devices)
        }
        return (device, token)
    }

    /// The device whose token this is, its last request noted; nil for any other token, or a QR code scanned too late.
    public func device(for token: String?, now: Date = Date()) -> PhoneDevice? {
        guard let token, !token.isEmpty else { return nil }
        let hash = Self.hash(token)
        return lock.withLock {
            var devices = stored()
            guard let index = devices.firstIndex(where: { $0.tokenHash == hash }) else { return nil }
            if devices[index].lastSeenAt == nil, now.timeIntervalSince(devices[index].pairedAt) >= Self.pairingLifetime { return nil }
            // Noted once a minute at most: the preferences are not written on every request.
            if devices[index].lastSeenAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
                devices[index].lastSeenAt = now
                save(devices)
            }
            return devices[index]
        }
    }

    public func remove(_ id: UUID) {
        lock.withLock { save(stored().filter { $0.id != id }) }
    }

    private func stored() -> [PhoneDevice] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([PhoneDevice].self, from: data)) ?? []
    }

    private func save(_ devices: [PhoneDevice]) {
        defaults.set(try? JSONEncoder().encode(devices), forKey: Self.key)
    }

    /// 32 random bytes, in base64 for a URL.
    static func newToken() -> String {
        let bytes = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
