import Foundation
import Security

/// Keychain storage for Podcast Index API key + secret (user-supplied; never hardcoded).
enum PodcastIndexKeychain {
    private static let service = "de.danoeh.antennapod.ios.podcastindex"
    private static let apiKeyAccount = "apiKey"
    private static let apiSecretAccount = "apiSecret"

    static var hasCredentials: Bool {
        guard let key = loadAPIKey(), let secret = loadAPISecret() else { return false }
        return !key.isEmpty && !secret.isEmpty
    }

    static func save(apiKey: String, apiSecret: String) throws {
        try save(account: apiKeyAccount, value: apiKey)
        try save(account: apiSecretAccount, value: apiSecret)
    }

    static func loadAPIKey() -> String? {
        load(account: apiKeyAccount)
    }

    static func loadAPISecret() -> String? {
        load(account: apiSecretAccount)
    }

    static func deleteCredentials() {
        delete(account: apiKeyAccount)
        delete(account: apiSecretAccount)
    }

    // MARK: - Private

    private static func save(account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    private static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return String(localized: "Keychain error (\(Int(status)))")
            }
        }
    }
}
