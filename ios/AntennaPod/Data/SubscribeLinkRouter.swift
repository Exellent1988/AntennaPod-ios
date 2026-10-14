import Foundation

/// Podcast subscribe links (`itpc://`, `pcast://`, `podcast://`, `feed:`, and
/// `antennapod://subscribe?url=…`). `RootTabView` shows the normal feed preview for the
/// resulting http(s) URL, or opens the podcast when it is already subscribed. Never
/// subscribes on its own.
@MainActor
final class SubscribeLinkRouter: ObservableObject {
    static let shared = SubscribeLinkRouter()

    /// http(s) feed URL waiting for `RootTabView`; cleared when it is consumed.
    @Published var pendingFeedUrl: String?
    /// New token when a link is consumed: `MiniPlayerView` closes the Full Player sheet, which
    /// would otherwise keep the root preview sheet from presenting.
    @Published private(set) var closeFullPlayerToken: UUID?

    func requestFullPlayerClose() {
        closeFullPlayerToken = UUID()
    }

    /// Returns `true` when `url` is a subscribe link (handled or rejected); `false` lets the
    /// playback deep-link router try it.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "antennapod" {
            guard url.host?.lowercased() == "subscribe" else { return false }
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value
            if let raw, let feedUrl = Self.httpURLString(raw) {
                pendingFeedUrl = feedUrl
            }
            return true
        }
        guard Self.subscribeSchemes.contains(scheme) else { return false }
        if let feedUrl = Self.feedURLString(fromSubscribeLink: url.absoluteString) {
            pendingFeedUrl = feedUrl
        }
        return true
    }

    nonisolated static let subscribeSchemes: Set<String> = ["itpc", "pcast", "podcast", "feed"]

    /// `itpc://host/path`, `pcast://…`, `podcast://host/path`, `feed://host/path` → `https://host/path`;
    /// `podcast://https://…`, `feed:https://…`, `feed://https://…` → the embedded URL. Query kept.
    /// Returns nil unless the result is an http(s) URL with a host.
    nonisolated static func feedURLString(fromSubscribeLink link: String) -> String? {
        guard let colon = link.firstIndex(of: ":") else { return nil }
        let scheme = link[..<colon].lowercased()
        guard subscribeSchemes.contains(scheme) else { return nil }
        var rest = String(link[link.index(after: colon)...])
        if rest.hasPrefix("//") {
            rest.removeFirst(2)
        }
        let lower = rest.lowercased()
        // feed:ftp://… / podcast://file://… — an embedded non-http(s) URL is rejected.
        if lower.range(of: "^[a-z][a-z0-9+.-]*://", options: .regularExpression) != nil,
           !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            return nil
        }
        let candidate = lower.hasPrefix("http://") || lower.hasPrefix("https://")
            ? rest
            : "https://" + rest
        return httpURLString(candidate)
    }

    nonisolated private static func httpURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return trimmed
    }
}
