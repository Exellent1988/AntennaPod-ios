import Foundation

extension PodcastEpisode {
    /// Prefer episode page/link URL; fall back to enclosure / media download URL.
    /// Local `file://` URLs are not shareable as network links.
    /// Does not invent URLs — returns nil when nothing network-shareable is known.
    /// For feed homepage / RSS fallback, call `shareURL(feed:)`.
    var shareURL: URL? {
        shareURL(feed: nil)
    }

    /// Best share URL for an episode:
    /// 1) episode `link` / website page
    /// 2) media `downloadUrl` / enclosure
    /// 3) feed homepage (`siteLink`)
    /// 4) feed RSS / subscription URL (`feedUrl`)
    /// Never invents a URL. Local `file://` and `local-folder://` feeds are omitted.
    func shareURL(feed: PodcastFeed?) -> URL? {
        if let link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: link), Self.isNetworkShareable(url) {
            return url
        }
        if let downloadUrl, !downloadUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: downloadUrl), Self.isNetworkShareable(url) {
            return url
        }
        if let feed {
            if let site = feed.siteLink?.trimmingCharacters(in: .whitespacesAndNewlines), !site.isEmpty,
               let url = URL(string: site), Self.isNetworkShareable(url) {
                return url
            }
            if let feedURL = feed.shareURL {
                return feedURL
            }
        }
        return nil
    }

    /// One-line share text for Messages/Mail: `"Title — Podcast"` when a feed title is known.
    func shareMessage(feedTitle: String?) -> String {
        let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let podcast = feedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty, !podcast.isEmpty {
            return "\(title) — \(podcast)"
        }
        if !title.isEmpty { return title }
        if !podcast.isEmpty { return podcast }
        return ""
    }

    private static func isNetworkShareable(_ url: URL) -> Bool {
        !url.isFileURL
            && url.scheme?.lowercased() != "local-folder"
            && !(url.absoluteString.lowercased().hasPrefix("local-folder:"))
    }

    /// Episode webpage from feed `link` only (`http` / `https`).
    /// Does **not** fall back to enclosure/`downloadUrl` (that is media, not a website)
    /// or to feed `siteLink` / RSS. Never invents a URL — nil when missing or non-http(s).
    var websiteURL: URL? {
        guard let link else { return nil }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}

extension PodcastFeed {
    /// Feed / podcast RSS (or Atom) URL for sharing the subscription.
    /// Local folder feeds (`local-folder://`) are omitted — no network feed URL.
    var shareURL: URL? {
        if LocalFolderFeed.isLocalFolderFeedURL(feedUrl) { return nil }
        let trimmed = feedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed), !url.isFileURL else { return nil }
        return url
    }
}
