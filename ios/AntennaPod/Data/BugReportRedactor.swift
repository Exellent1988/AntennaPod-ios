import Foundation

/// Strips secrets from bug-report text before the user sees, copies or shares it
/// (Android BugReportActivity has no redaction; the iOS port adds it because the log is shared).
/// Covers: URL userinfo (`https://user:pass@host`), sensitive query parameters, auth headers and
/// Bearer/Basic credentials, `key=value` / `key: value` / JSON pairs with secret-like keys, and
/// literal known secrets (gpodder/Nextcloud username and password, Podcast Index key/secret).
enum BugReportRedactor {
    static let placeholder = "<redacted>"

    /// Query / form parameter names whose values are dropped.
    static let sensitiveParameterNames = [
        "token", "access_token", "refresh_token", "id_token", "auth", "authorization", "api_key", "apikey",
        "key", "secret", "client_secret", "password", "passwd", "pass", "pwd", "signature", "sig",
        "session", "sessionid", "sid", "code", "x-amz-signature", "x-amz-credential", "x-amz-security-token",
    ]

    /// Keys in `key=value`, `key: value` and JSON `"key": "value"` whose values are dropped.
    static let sensitiveKeyNames = [
        "password", "passwd", "pwd", "pass", "token", "access_token", "refresh_token", "accessToken",
        "refreshToken", "secret", "api_key", "apiKey", "apiSecret", "api_secret", "gpodderPassword",
        "gpodder_password", "gpodderUsername", "gpodder_username", "username", "user", "login",
        "cookie", "set-cookie", "authorization", "proxy-authorization", "x-api-key", "x-auth-key",
    ]

    /// RFC 3986 unreserved characters; everything else is percent-encoded (catches `&` → `%26`).
    private static let unreservedURLCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func redact(_ text: String, knownSecrets: [String] = []) -> String {
        var s = text
        // Literal secrets first (longest first so a password containing the username is caught whole).
        for secret in knownSecrets.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ $0.count >= 3 }).sorted(by: { $0.count > $1.count }) {
            s = s.replacingOccurrences(of: secret, with: placeholder)
            if let enc = secret.addingPercentEncoding(withAllowedCharacters: unreservedURLCharacters), enc != secret {
                s = s.replacingOccurrences(of: enc, with: placeholder)
            }
        }
        // URL userinfo: scheme://user[:pass]@host
        s = replace(#"([A-Za-z][A-Za-z0-9+.\-]*://)[^/\s@?#]+@"#, in: s, with: "$1\(placeholder)@")
        // Auth / cookie headers: whole value to end of line.
        s = replace(#"(?i)\b(authorization|proxy-authorization|x-api-key|x-auth-key|cookie|set-cookie)(["']?\s*[:=]\s*)[^\r\n]*"#,
                    in: s, with: "$1$2\(placeholder)")
        // Bearer / Basic credentials anywhere.
        s = replace(#"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=\-]{6,}"#, in: s, with: "$1 \(placeholder)")
        // Query / fragment parameters.
        let params = sensitiveParameterNames.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        s = replace(#"(?i)([?&#;](?:"# + params + #")=)[^&#\s"'<>]*"#, in: s, with: "$1\(placeholder)")
        // JSON "key": "value"
        let keys = sensitiveKeyNames.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        s = replace(#"(?i)("(?:"# + keys + #")"\s*:\s*)"(?:[^"\\]|\\.)*""#, in: s, with: "$1\"\(placeholder)\"")
        // key=value / key: value (unquoted)
        s = replace(#"(?i)(?<![\w\-])((?:"# + keys + #")\s*[:=]\s*)(?!\#(placeholder))(?!")[^\s,;&}\]]+"#,
                    in: s, with: "$1\(placeholder)")
        return s
    }

    private static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
