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
        shareMessage(feedTitle: feedTitle, positionSeconds: nil)
    }

    /// Share text with optional human-readable playback position.
    /// When `positionSeconds` is a finite non-negative value, appends ` (m:ss)` or ` (h:mm:ss)`
    /// using the same formatter as the full-player scrubber — e.g. `Title — Podcast (12:34)`.
    /// Does **not** append `#t=` / media deep-link fragments (text timestamp only).
    func shareMessage(feedTitle: String?, positionSeconds: Double?) -> String {
        let base: String = {
            let title = self.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let podcast = feedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty, !podcast.isEmpty {
                return "\(title) — \(podcast)"
            }
            if !title.isEmpty { return title }
            if !podcast.isEmpty { return podcast }
            return ""
        }()
        guard let position = Self.formatPlaybackPosition(positionSeconds) else {
            return base
        }
        if base.isEmpty { return "(\(position))" }
        return "\(base) (\(position))"
    }

    /// Human-readable playback position (`m:ss` / `h:mm:ss`), matching full-player `format(_:)`.
    /// Returns `nil` when seconds are missing, non-finite, or negative.
    static func formatPlaybackPosition(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Whether a playback position is known well enough to offer “Share with position”.
    static func canShareWithPosition(_ seconds: Double?) -> Bool {
        formatPlaybackPosition(seconds) != nil
    }

    private static func isNetworkShareable(_ url: URL) -> Bool {
        !url.isFileURL
            && url.scheme?.lowercased() != "local-folder"
            && !(url.absoluteString.lowercased().hasPrefix("local-folder:"))
    }

    /// Episode webpage from feed `link` only (`http` / `https`).
    /// Does **not** fall back to enclosure/`downloadUrl` (that is media, not a website)
    /// or to feed `siteLink` / RSS. Never invents a URL — nil when missing or non-http(s).
    /// A space in the feed link is percent-encoded (`EpisodeMediaURL`) so Open episode website still appears.
    /// `URL(string:)` alone drops that link.
    var websiteURL: URL? {
        guard let parsed = EpisodeMediaURL.url(from: link) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// Trimmed feed-provided enclosure / media URL when it has an `http(s)` scheme.
    /// Keeps the raw string for sharing/copying when Foundation cannot make a URL value.
    /// Never invents a URL; local `file://` / `local-folder://` values are omitted.
    var mediaURLString: String? {
        guard let downloadUrl else { return nil }
        let trimmed = downloadUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil else { return nil }
        return trimmed
    }

    /// Enclosure / media download URL (`http` / `https` only), when parseable.
    /// Distinct from `websiteURL` (episode page). Never invents a URL; `file://` /
    /// `local-folder://` omitted. Used to prefer URL-typed sharing over raw text.
    var mediaURL: URL? {
        guard let raw = mediaURLString else { return nil }
        return URL(string: raw)
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

    /// Podcast homepage from feed `siteLink` only (`http` / `https`).
    /// Does **not** fall back to feed RSS / `feedUrl` (that is the subscription URL, not a website).
    /// Never invents a URL — nil when missing or non-http(s). Distinct from `PodcastEpisode.websiteURL`
    /// (episode page) and from in-app **Open podcast** (Subscriptions → Feed detail).
    /// A space in the feed website is percent-encoded (`EpisodeMediaURL`) so Open podcast website still appears.
    /// `URL(string:)` alone drops that link.
    var websiteURL: URL? {
        guard let parsed = EpisodeMediaURL.url(from: siteLink) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// Funding / Support page from feed `fundingUrl` only (`http` / `https`).
    /// From Podcast Index `podcast:funding` or Atom `link rel="payment"` — never invents Patreon/etc.
    /// Distinct from `websiteURL` (homepage) and feed RSS/`feedUrl`. Nil when missing or non-http(s).
    /// A space in the feed funding address is percent-encoded (`EpisodeMediaURL`) so Support still appears.
    /// `URL(string:)` alone drops that link.
    var fundingURL: URL? {
        guard let parsed = EpisodeMediaURL.url(from: fundingUrl) else { return nil }
        let scheme = parsed.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// Menu title for Support / Funding: feed-provided label when present, else localized **Support**.
    var supportActionTitle: String {
        displayFundingLabel ?? String(localized: "Support")
    }

    /// VoiceOver label: prefer feed label, else **Support**.
    var supportAccessibilityLabel: String {
        displayFundingLabel ?? String(localized: "Support")
    }
}
