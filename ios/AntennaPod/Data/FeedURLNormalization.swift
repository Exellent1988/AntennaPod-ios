import Foundation

/// Trim / normalize user-entered or pasteboard RSS/Atom feed URLs before Preview / subscribe.
/// Prefers `https://` when the scheme is missing and the string looks like a host+path — never invents
/// non-http(s) schemes, and never auto-subscribes.
enum FeedURLNormalization {
    enum Outcome: Equatable {
        case ok(String)
        case empty
        case invalid
    }

    /// Normalize raw text into an http(s) feed URL string suitable for `FeedPreviewRequest` / `FeedRepository`.
    static func normalize(_ raw: String) -> Outcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let firstLine = trimmed
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? trimmed

        var candidate = firstLine
        // Angle brackets often wrap URLs in plain text / email.
        if candidate.hasPrefix("<"), candidate.hasSuffix(">"), candidate.count > 2 {
            candidate = String(candidate.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !candidate.isEmpty else { return .empty }

        // Pasted subscribe links (itpc://, podcast://, feed:…) failed the http(s) check below;
        // rewrite them the same way an opened link is (`SubscribeLinkRouter`).
        if let rewritten = SubscribeLinkRouter.feedURLString(fromSubscribeLink: candidate) {
            candidate = rewritten
        }

        // Scheme missing: safe https default when it looks like a host/path (not a relative path alone).
        if !candidate.contains("://") {
            if candidate.hasPrefix("//") {
                candidate = "https:" + candidate
            } else if looksLikeHostPath(candidate) {
                candidate = "https://" + candidate
            } else {
                return .invalid
            }
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            return .invalid
        }

        // Prefer a stable absolute string; fall back to the candidate we built.
        let normalized = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return .ok(normalized.isEmpty ? candidate : normalized)
    }

    /// Loose match key for already-subscribed detection (case, trailing slash, http↔https).
    static func canonicalKey(_ feedUrl: String) -> String {
        guard case .ok(let normalized) = normalize(feedUrl),
              let url = URL(string: normalized)
        else {
            return feedUrl
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        var path = url.path
        if path.count > 1, path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        let host = (url.host ?? "").lowercased()
        let query = url.query.map { "?\($0)" } ?? ""
        // Scheme-agnostic so https://x and http://x collide as the same subscription.
        return "\(host)\(path)\(query)"
    }

    /// Removes `user:password@` from a feed URL for anything shown, copied, shared, or exported
    /// (OPML, HTML, plain text). Other strings are returned unchanged. The stored feed URL keeps
    /// its userinfo because refresh may rely on it.
    static func strippingCredentials(_ feedUrl: String) -> String {
        guard feedUrl.contains("@"),
              var components = URLComponents(string: feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.user != nil || components.password != nil
        else {
            return feedUrl
        }
        components.user = nil
        components.password = nil
        return components.string ?? feedUrl
    }

    /// First library feed whose canonical URL matches `feedUrl`, if any.
    static func subscribedFeed(matching feedUrl: String, in feeds: [PodcastFeed]) -> PodcastFeed? {
        let key = canonicalKey(feedUrl)
        guard !key.isEmpty else { return nil }
        return feeds.first { canonicalKey($0.feedUrl) == key }
    }

    /// True when the string looks like `host` or `host/path` (no spaces; has a dot or is localhost).
    private static func looksLikeHostPath(_ s: String) -> Bool {
        guard !s.contains(where: { $0.isWhitespace }), !s.isEmpty else { return false }
        if s.hasPrefix("/") { return false }
        let hostPart = s.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
        let hostOnly = hostPart.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostPart
        if hostOnly.lowercased() == "localhost" { return true }
        // Require at least one dot so "feed" alone is not treated as a host.
        return hostOnly.contains(".")
    }
}
