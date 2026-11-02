import Foundation
import Security

/**
 * Server passwords live in the iOS Keychain. Subsonic token auth needs the
 * plain password on every request (the token is md5(password + salt)), so it
 * has to be kept — this way it is at least sealed by the system, never in a
 * preferences file.
 */
enum Keychain {
    private static let service = "app.kultr.ios.servers"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func set(_ password: String, for account: String) -> Bool {
        delete(account)
        var attributes = query(account)
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /** Nil when there is nothing stored, or it cannot be read (say, after re-signing with another Apple ID). */
    static func get(_ account: String) -> String? {
        var query = Self.query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
