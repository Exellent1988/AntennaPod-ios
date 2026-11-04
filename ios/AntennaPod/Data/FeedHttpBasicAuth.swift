import Foundation

/// Username + password for per-feed HTTP Basic authentication (private feeds).
/// Passwords live only in the Keychain — never in `feed-settings.json` / backup ZIP.
struct FeedHttpBasicCredentials: Equatable, Hashable {
    var username: String
    var password: String

    /// Trimmed username non-empty (password may be empty for some servers).
    var isUsable: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Helpers to attach HTTP Basic `Authorization` for feed refresh + same-host media downloads.
/// **Never logs passwords.** Local-folder feeds are out of scope (no network auth).
enum FeedHttpBasicAuth {
    /// `Basic base64(user:pass)` value for the Authorization header.
    static func authorizationHeaderValue(username: String, password: String) -> String {
        let raw = "\(username):\(password)"
        let basic = Data(raw.utf8).base64EncodedString()
        return "Basic \(basic)"
    }

    /// Sets `Authorization: Basic …` when credentials are usable. Does not clear other headers.
    static func apply(_ credentials: FeedHttpBasicCredentials?, to request: inout URLRequest) {
        guard let credentials, credentials.isUsable else { return }
        let value = authorizationHeaderValue(
            username: credentials.trimmedUsername,
            password: credentials.password
        )
        request.setValue(value, forHTTPHeaderField: "Authorization")
    }

    /// True when `requestURL` host equals the feed URL host (case-insensitive).
    /// Media on a different CDN host does **not** get proactive Basic auth (honest scope).
    static func hostMatches(requestURL: URL, feedURLString: String) -> Bool {
        guard let feedURL = URL(string: feedURLString),
              let requestHost = requestURL.host?.lowercased(),
              let feedHost = feedURL.host?.lowercased(),
              !requestHost.isEmpty,
              !feedHost.isEmpty
        else {
            return false
        }
        return requestHost == feedHost
    }

    /// Honest user-facing copy when the server returns HTTP 401 for a feed request.
    static var unauthorizedFeedMessage: String {
        String(
            localized: "Feed server returned HTTP 401 Unauthorized. Enter username and password under Podcast settings → Authentication (stored in Keychain), then refresh. Local folder feeds do not use HTTP auth."
        )
    }

    /// Honest user-facing copy when a media download returns HTTP 401.
    static var unauthorizedDownloadMessage: String {
        String(
            localized: "Download failed (HTTP 401 Unauthorized). Check Podcast settings → Authentication for this podcast (Keychain). Auth applies to the feed host only — not other CDN hosts. Streaming without download may still fail."
        )
    }
}
