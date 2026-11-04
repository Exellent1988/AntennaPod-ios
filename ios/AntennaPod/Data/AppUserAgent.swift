import Foundation

/// Shared User-Agent for feed refresh, media downloads, and other URLSession clients.
/// Optional Settings override (empty → app default). Newlines are stripped (header safety).
/// **Not** applied to stock `AVPlayer` streaming (system UA) — honesty documented in Settings / docs.
/// For HTTP(S) proxy see `AppHTTPProxy` / Settings → Network / Downloads → HTTP proxy (not this type).
enum AppUserAgent {
    /// Default when Settings override is empty after sanitize.
    static let defaultValue = "AntennaPod-iOS/0.1"

    /// Same key as `AppSettings.Keys.customUserAgent` (UserDefaults).
    static let userDefaultsKey = "settings.customUserAgent"

    /// Strip CR/LF (and other ISO controls) and trim — prevents header injection; no proxy inventing.
    static func sanitize(_ raw: String) -> String {
        let stripped = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) {
                return " "
            }
            return Character(scalar)
        }
        let joined = String(stripped)
        return joined
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolved UA: non-empty sanitized override, else `defaultValue`.
    /// - Parameter override: When `nil`, reads UserDefaults (live Settings). Pass an explicit
    ///   string when applying from an already-loaded `AppSettings` value.
    static func resolved(override: String? = nil) -> String {
        let raw: String
        if let override {
            raw = override
        } else {
            raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
        }
        let sanitized = sanitize(raw)
        return sanitized.isEmpty ? defaultValue : sanitized
    }

    /// Sets `User-Agent` on the request (does not clear other headers).
    static func apply(to request: inout URLRequest, override: String? = nil) {
        request.setValue(resolved(override: override), forHTTPHeaderField: "User-Agent")
    }
}
