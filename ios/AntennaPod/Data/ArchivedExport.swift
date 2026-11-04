import Foundation

/// Plain-text export of the **full** persisted Archived catalog (`PodcastStore.archivedEpisodes`).
/// Catalog order is newest archived first — never podcast-chip / search / UI `archivedSort` filtered subsets.
/// One line per episode: `1. Episode title — Feed display title` (1-based index).
/// Local plain text only — not OPML, not gpodder, not a deep link.
enum ArchivedExport {
    /// Body only (no “Archived” header). Empty when `episodes` is empty.
    static func plainText(
        episodes: [PodcastEpisode],
        feedTitleFor: (PodcastEpisode) -> String
    ) -> String {
        guard !episodes.isEmpty else { return "" }
        return episodes.enumerated().map { index, episode in
            line(index: index + 1, episode: episode, feedTitle: feedTitleFor(episode))
        }.joined(separator: "\n")
    }

    /// System share payload: localized “Archived” header + blank line + body (same body as `plainText`).
    /// Empty when `episodes` is empty.
    static func shareText(
        episodes: [PodcastEpisode],
        feedTitleFor: (PodcastEpisode) -> String
    ) -> String {
        let body = plainText(episodes: episodes, feedTitleFor: feedTitleFor)
        guard !body.isEmpty else { return "" }
        let header = String(localized: "Archived")
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
