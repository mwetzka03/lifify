import Foundation
import Security

/// Stores secrets in the iOS Keychain.
public enum KeychainStore {
    public static let nutritionService = "lifify.nutrition"
    /// Session cookie for a manual Trade Republic sign-in. Not the nutrition key.
    public static let tradeRepublicService = "lifify.traderepublic"
    public static let tradeRepublicAccount = "session"
    /// This device only, so the item is left out of backups. Same rule as the Gemini key.
    public static var deviceOnly: String { kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String }

    /// Replaces the stored secret.
    public static func set(_ value: String, account: String, service: String = nutritionService) {
        remove(account: account, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: deviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Reads a stored secret.
    public static func string(account: String, service: String = nutritionService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    /// Deletes a stored secret.
    public static func remove(account: String, service: String = nutritionService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
