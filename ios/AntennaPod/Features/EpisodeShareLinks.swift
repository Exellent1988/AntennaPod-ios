import SwiftUI

/// Label-style **Share** + optional **Share with position** for an episode.
///
/// Reuses `PodcastEpisode.shareURL` / `shareMessage` / `canShareWithPosition`:
/// URL precedence link → enclosure → siteLink → feedUrl; omits `file://` /
/// `local-folder`. Position appends a human-readable timestamp to the message
/// only — **no** `#t=` / deep-link fragments. Emits nothing when nothing
/// network-shareable is known (hidden, same as Full player).
///
/// `@ViewBuilder` so callers in `HStack` / `Menu` get sibling controls (not one
/// nested wrapper). Used by Full player secondary + mini player ⋯.
enum EpisodeShareLinks {
    /// Shares only the feed-provided episode webpage URL (`link`).
    /// This is intentionally distinct from generic **Share episode**, which may fall back
    /// to an enclosure or feed URL when the webpage link is absent.
    @ViewBuilder
    static func episodeLinkLabelStyle(episode: PodcastEpisode) -> some View {
        if let url = episode.websiteURL {
            let message = episodeLinkShareMessage(for: episode)
            ShareLink(
                item: url,
                subject: Text(message),
                message: Text(message)
            ) {
                Label("Share episode link", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(String(localized: "Share episode link"))
            .accessibilityHint(
                String(localized: "Opens the system share sheet with the episode title and episode webpage URL")
            )
        }
    }

    private static func episodeLinkShareMessage(for episode: PodcastEpisode) -> String {
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkLabel = String(localized: "Episode link")
        return title.isEmpty ? linkLabel : "\(title) — \(linkLabel)"
    }

    @ViewBuilder
    static func labelStyle(
        episode: PodcastEpisode,
        feed: PodcastFeed?,
        positionSeconds: Double?,
        feedDisplayTitle: String? = nil
    ) -> some View {
        let shownFeedTitle = {
            let trimmed = feedDisplayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
            return feed?.title
        }()
        mediaURLLabelStyle(episode: episode)
        if let url = episode.shareURL(feed: feed) {
            ShareLink(
                item: url,
                subject: Text(episode.title),
                message: Text(episode.shareMessage(feedTitle: shownFeedTitle))
            ) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(String(localized: "Share episode"))
            .accessibilityHint(String(localized: "Opens the system share sheet with the episode title and link"))

            if PodcastEpisode.canShareWithPosition(positionSeconds) {
                ShareLink(
                    item: url,
                    subject: Text(episode.title),
                    message: Text(
                        episode.shareMessage(
                            feedTitle: shownFeedTitle,
                            positionSeconds: positionSeconds
                        )
                    )
                ) {
                    Label("Share with position", systemImage: "square.and.arrow.up.on.square")
                }
                .accessibilityLabel(String(localized: "Share with position"))
                .accessibilityHint(
                    String(localized: "Opens the system share sheet with the episode title, link, and a readable position timestamp in the message. The shared link is unchanged — no #t= seek fragment.")
                )
            }
        }
    }

    /// Shares the same feed-provided media/enclosure URL exposed by Copy media URL.
    /// URL values are preferred; an http(s) raw string is retained as a fallback.
    @ViewBuilder
    static func mediaURLLabelStyle(episode: PodcastEpisode) -> some View {
        if let rawMediaURL = episode.mediaURLString {
            if let mediaURL = episode.mediaURL {
                mediaURLShareLink(item: mediaURL, episode: episode)
            } else {
                mediaURLShareLink(item: rawMediaURL, episode: episode)
            }
        }
    }

    private static func mediaURLShareMessage(for episode: PodcastEpisode) -> String {
        let title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaLabel = String(localized: "Media URL")
        return title.isEmpty ? mediaLabel : "\(title) — \(mediaLabel)"
    }

    private static func mediaURLShareLink<Item: Transferable>(
        item: Item,
        episode: PodcastEpisode
    ) -> some View {
        let message = mediaURLShareMessage(for: episode)
        return ShareLink(
            item: item,
            subject: Text(message),
            message: Text(message)
        ) {
            Label("Share media URL", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel(String(localized: "Share media URL"))
        .accessibilityHint(
            String(localized: "Opens the system share sheet with the episode title and media / enclosure URL")
        )
    }
}
