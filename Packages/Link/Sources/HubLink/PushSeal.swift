import CryptoKit
import Foundation

/// What a notification says, sealed for the iPhone that made the key (20/11): Apple's push service carries it without
/// being able to read it, and the iPhone's notification extension opens it.
public struct PushContent: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String?
    public var body: String

    public init(title: String, subtitle: String?, body: String) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
    }
}

/// AES-GCM with a 256-bit key the iPhone makes once and gives to the Mac with its notifications' address, through the
/// private network or the user's iCloud; it never goes through Apple's push service.
public enum PushSeal {
    /// A new key, in base64: 32 random bytes.
    public static func newKey() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Whether this text is a key: base64 of 32 bytes.
    public static func isKey(_ text: String) -> Bool {
        Data(base64Encoded: text)?.count == 32
    }

    public static func seal(_ content: PushContent, key: String) throws -> String {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
        let box = try AES.GCM.seal(try JSONEncoder().encode(content), using: SymmetricKey(data: bytes))
        guard let combined = box.combined else { throw CryptoKitError.incorrectParameterSize }
        return combined.base64EncodedString()
    }

    /// The content, or nil when the key is not the one it was sealed with.
    public static func open(_ sealed: String, key: String) -> PushContent? {
        guard let bytes = Data(base64Encoded: key), bytes.count == 32, let combined = Data(base64Encoded: sealed),
              let box = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(box, using: SymmetricKey(data: bytes)) else { return nil }
        return try? JSONDecoder().decode(PushContent.self, from: plain)
    }
}
