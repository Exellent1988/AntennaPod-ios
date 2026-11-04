import Foundation
import Security

/// Keychain storage for parental-controls PIN (4–6 digits). Never written to UserDefaults or backup ZIP.
enum ParentalControlsKeychain {
    private static let service = "de.danoeh.antennapod.ios.parental"
    private static let account = "pin"

    static var hasPIN: Bool {
        guard let pin = loadPIN() else { return false }
        return isValidPIN(pin)
    }

    static func savePIN(_ pin: String) throws {
        guard isValidPIN(pin) else {
            throw KeychainError.invalidPIN
        }
        let data = Data(pin.utf8)
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

    static func loadPIN() -> String? {
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

    static func verifyPIN(_ pin: String) -> Bool {
        guard let stored = loadPIN() else { return false }
        return stored == pin
    }

    static func deletePIN() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// 4–6 numeric digits only.
    static func isValidPIN(_ pin: String) -> Bool {
        let trimmed = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...6).contains(trimmed.count) else { return false }
        return trimmed.allSatisfy(\.isNumber)
    }

    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)
        case invalidPIN

        var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                return String(localized: "Keychain error (\(Int(status)))")
            case .invalidPIN:
                return String(localized: "PIN must be 4–6 digits")
            }
        }
    }
}
