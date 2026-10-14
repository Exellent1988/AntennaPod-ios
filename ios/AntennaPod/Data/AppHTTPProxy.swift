import Foundation
import Security
import CFNetwork

/// Optional HTTP(S) proxy for URLSession-based networking (Android AntennaPod parity lite).
/// Host/port/username + enable live in UserDefaults / backup; **password Keychain only**
/// (never UserDefaults / never JSON backup plaintext — same pattern as HTTP Basic / gpodder).
///
/// **Honest limits:** applies to app `URLSession` clients (feeds / downloads / search / …).
/// Stock `AVPlayer` streaming may bypass this proxy (system / no custom `AVURLAsset` inventing).
/// **Not** VPN detection; **not** certificate pinning; **not** SOCKS in v1 (HTTP/HTTPS only).
enum AppHTTPProxy {
    /// Same keys as `AppSettings.Keys` (UserDefaults).
    static let enabledKey = "settings.httpProxy.enabled"
    static let hostKey = "settings.httpProxy.host"
    static let portKey = "settings.httpProxy.port"
    static let usernameKey = "settings.httpProxy.username"

    /// Posted when enable/host/port/username/password change so session factories can refresh.
    static let didChangeNotification = Notification.Name("AppHTTPProxy.didChange")

    /// Default port shown when the field is empty (not applied until enable + valid host).
    static let defaultPort = 8080

    // MARK: - Sanitize

    /// Trim; strip schemes (`http://`, `https://`); remove CR/LF/controls; collapse whitespace.
    /// Empty → treat as no host (proxy ignored even when enable is on).
    static func sanitizeHost(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        for prefix in ["https://", "http://"] {
            if lower.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        // Drop any path/query the user may have pasted with a URL.
        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }
        if let at = s.firstIndex(of: "@") {
            // user:pass@host → host only (credentials belong in username/password fields).
            s = String(s[s.index(after: at)...])
        }
        let stripped = s.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                return " "
            }
            return Character(scalar)
        }
        return String(stripped)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Port 1…65535; `nil` / out of range → invalid.
    static func sanitizePort(_ raw: Int) -> Int? {
        guard (1...65535).contains(raw) else { return nil }
        return raw
    }

    /// Parse port from a text field; empty → `nil` (invalid until set).
    static func parsePort(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
        return sanitizePort(value)
    }

    static func sanitizeUsername(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: - Resolve

    /// Effective proxy when enable is on and host+port are valid; otherwise `nil` (disabled / ignored).
    static func resolved(
        enabled: Bool? = nil,
        host: String? = nil,
        port: Int? = nil,
        username: String? = nil,
        password: String? = nil
    ) -> Resolved? {
        let on = enabled ?? UserDefaults.standard.bool(forKey: enabledKey)
        guard on else { return nil }
        let h = sanitizeHost(host ?? UserDefaults.standard.string(forKey: hostKey) ?? "")
        guard !h.isEmpty else { return nil }
        let storedPort: Int = {
            if let port { return port }
            if UserDefaults.standard.object(forKey: portKey) != nil {
                return UserDefaults.standard.integer(forKey: portKey)
            }
            // Missing key → display default (8080), same as AppSettings init.
            return defaultPort
        }()
        guard let p = sanitizePort(storedPort) else { return nil }
        let user = sanitizeUsername(username ?? UserDefaults.standard.string(forKey: usernameKey) ?? "")
        let pass = password ?? AppHTTPProxyKeychain.loadPassword() ?? ""
        return Resolved(host: h, port: p, username: user, password: pass)
    }

    /// Signature of the active proxy config (for session cache invalidation). No password in logs —
    /// includes a boolean “has password” only.
    static func configurationSignature(from resolved: Resolved? = AppHTTPProxy.resolved()) -> String {
        guard let r = resolved else { return "off" }
        let userPart = r.username.isEmpty ? "-" : r.username
        let passPart = r.password.isEmpty ? "0" : "1"
        return "\(r.host)|\(r.port)|\(userPart)|\(passPart)"
    }

    /// Apply `connectionProxyDictionary` for HTTP + HTTPS when resolved; clear when `nil`.
    static func apply(to configuration: URLSessionConfiguration, resolved: Resolved? = AppHTTPProxy.resolved()) {
        guard let r = resolved else {
            configuration.connectionProxyDictionary = nil
            return
        }
        var dict: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPProxy: r.host,
            kCFNetworkProxiesHTTPPort: r.port,
            // HTTPS proxy keys are macOS-only symbols; use their CFNetwork string values on iOS.
            "HTTPSEnable": true,
            "HTTPSProxy": r.host,
            "HTTPSPort": r.port,
        ]
        if !r.username.isEmpty {
            dict[kCFProxyUsernameKey] = r.username
            dict[kCFProxyPasswordKey] = r.password
        }
        configuration.connectionProxyDictionary = dict
    }

    /// Notify listeners (AppURLSession / DownloadService) after prefs change.
    static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    struct Resolved: Equatable {
        var host: String
        var port: Int
        var username: String
        var password: String

        var hasCredentials: Bool { !username.isEmpty }
    }
}

/// Proxy password in the Keychain (never plaintext in UserDefaults / iOS JSON backup).
enum AppHTTPProxyKeychain {
    private static let service = "de.danoeh.antennapod.ios.http-proxy"
    private static let account = "password"

    static func savePassword(_ password: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        // Empty password: delete only (optional auth).
        guard !password.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func loadPassword() -> String? {
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

    static func hasStoredPassword() -> Bool {
        guard let p = loadPassword(), !p.isEmpty else { return false }
        return true
    }

    static func deletePassword() {
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
                return "Keychain error (\(status))"
            }
        }
    }
}
