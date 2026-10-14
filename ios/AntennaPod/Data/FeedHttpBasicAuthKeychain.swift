import Foundation
import Security

/// Per-feed HTTP Basic credentials in the Keychain (never plaintext in `feed-settings.json`).
/// Account keys are feed UUID + field; passwords are never logged.
enum FeedHttpBasicAuthKeychain {
    private static let service = "de.danoeh.antennapod.ios.feed-http-basic"
    private static let usernameSuffix = "|username"
    private static let passwordSuffix = "|password"

    static func hasCredentials(for feedId: UUID) -> Bool {
        guard let creds = load(for: feedId) else { return false }
        return creds.isUsable
    }

    static func save(username: String, password: String, for feedId: UUID) throws {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else {
            throw KeychainError.emptyUsername
        }
        try save(account: account(feedId, usernameSuffix), value: user)
        try save(account: account(feedId, passwordSuffix), value: password)
    }

    static func load(for feedId: UUID) -> FeedHttpBasicCredentials? {
        guard let username = load(account: account(feedId, usernameSuffix)),
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        let password = load(account: account(feedId, passwordSuffix)) ?? ""
        return FeedHttpBasicCredentials(username: username, password: password)
    }

    /// Username only (safe to show in UI). Password is never returned for display once saved
    /// — callers should leave the SecureField empty and show “Stored in Keychain”.
    static func loadUsername(for feedId: UUID) -> String? {
        load(for: feedId)?.trimmedUsername
    }

    static func delete(for feedId: UUID) {
        delete(account: account(feedId, usernameSuffix))
        delete(account: account(feedId, passwordSuffix))
    }

    // MARK: - Private

    private static func account(_ feedId: UUID, _ suffix: String) -> String {
        feedId.uuidString + suffix
    }

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
        case emptyUsername
        case unhandled(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyUsername:
                return String(localized: "Username is required for HTTP authentication")
            case .unhandled(let status):
                return String(localized: "Keychain error (\(Int(status)))")
            }
        }
    }
}
