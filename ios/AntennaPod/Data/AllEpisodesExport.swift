import Foundation

/// Plain-text export of the **soft-capped** All Episodes catalog (`PodcastStore.allEpisodes`,
/// newest **500** by `pubDateEpochMs`).
/// Catalog order is newest-first store order — never status/podcast/type/search /
/// UI `allEpisodesSort` filtered subsets; **never** invents episodes beyond the soft cap.
/// One line per episode: `1. Episode title — Feed display title` (1-based index).
/// Local plain text only — not OPML, not gpodder, not a deep link.
enum AllEpisodesExport {
    /// Body only (no “Episodes” header). Empty when `episodes` is empty.
    static func plainText(
        episodes: [PodcastEpisode],
        feedTitleFor: (PodcastEpisode) -> String
    ) -> String {
        guard !episodes.isEmpty else { return "" }
        return episodes.enumerated().map { index, episode in
            line(index: index + 1, episode: episode, feedTitle: feedTitleFor(episode))
        }.joined(separator: "\n")
    }

    /// System share payload: localized “Episodes” header + blank line + body (same body as `plainText`).
    /// Empty when `episodes` is empty. Header matches nav title / ShareLink subject.
    static func shareText(
        episodes: [PodcastEpisode],
        feedTitleFor: (PodcastEpisode) -> String
    ) -> String {
        let body = plainText(episodes: episodes, feedTitleFor: feedTitleFor)
        guard !body.isEmpty else { return "" }
        let header = String(localized: "Episodes")
        return "\(header)\n\n\(body)"
    }

    private static func line(index: Int, episode: PodcastEpisode, feedTitle: String) -> String {
        var title = episode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = String(localized: "Episode")
        }
        var feed = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if feed.isEmpty {
            feed = String(localized: "Podcast")
        }
        return "\(index). \(title) — \(feed)"
    }
}
