import Foundation
import HubLink
import Security

/// The key the iPhone's notifications are sealed with (20/11): made once on the iPhone, kept in a Keychain group the app
/// shares with its notification extension, which opens them; given to the Mac with the notifications' address, never to
/// Apple's push service.
enum PushKeyStore {
    static let group = "CQ43U6XX4Z.fr.paulmailhes.polhub.ios.partage"
    static let service = "fr.paulmailhes.polhub.ios.notifications"

    static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "cle",
         kSecAttrAccessGroup as String: group]
    }

    /// The key; made and kept when `create` and there is none yet.
    static func key(create: Bool) -> String? {
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let key = String(data: data, encoding: .utf8), PushSeal.isKey(key) {
            return key
        }
        guard create else { return nil }
        let key = PushSeal.newKey()
        var item = base()
        item[kSecValueData as String] = Data(key.utf8)
        // The extension opens a notification while the iPhone is locked, once unlocked since it started.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(base() as CFDictionary)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}
