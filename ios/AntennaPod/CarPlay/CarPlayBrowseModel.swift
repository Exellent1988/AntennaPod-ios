import Foundation

/// UIKit-free model for CarPlay browse lists (unit-testable without CarPlay framework).
struct CarPlayRow: Equatable {
    enum Target: Equatable {
        case feed(UUID)
        case episode(String)
    }
    var title: String
    var detail: String?
    var imageUrl: String?
    var target: Target
}

enum CarPlayBrowseModel {
    /// CarPlay list templates are capped by `CPListTemplate.maximumItemCount` (typically 12–100);
    /// we cap conservatively and let the template clamp further.
    static let maxRows = 100

    static func subscriptionRows(_ feeds: [PodcastFeed]) -> [CarPlayRow] {
        feeds
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(maxRows)
            .map { CarPlayRow(title: $0.title, detail: $0.author, imageUrl: $0.imageUrl, target: .feed($0.id)) }
    }

    /// Newest first; episodes without a date go last.
    static func episodeRows(_ episodes: [PodcastEpisode], feedTitle: String? = nil) -> [CarPlayRow] {
        episodes
            .sorted { newerFirst($0.pubDateEpochMs, $1.pubDateEpochMs) }
            .prefix(maxRows)
            .map { episodeRow($0, detail: feedTitle) }
    }

    /// Queue keeps user order.
    static func queueRows(_ queue: [PodcastEpisode], feedTitleFor: (PodcastEpisode) -> String?) -> [CarPlayRow] {
        queue.prefix(maxRows).map { episodeRow($0, detail: feedTitleFor($0)) }
    }

    static func downloadRows(
        feeds: [PodcastFeed],
        isDownloaded: (PodcastEpisode) -> Bool
    ) -> [CarPlayRow] {
        var seen = Set<String>()
        var pairs: [(PodcastEpisode, String)] = []
        for feed in feeds {
            for ep in feed.episodes where isDownloaded(ep) && seen.insert(ep.id).inserted {
                pairs.append((ep, feed.title))
            }
        }
        return pairs
            .sorted { newerFirst($0.0.pubDateEpochMs, $1.0.pubDateEpochMs) }
            .prefix(maxRows)
            .map { episodeRow($0.0, detail: $0.1) }
    }

    /// Sort predicate: newer dates first, undated items last.
    static func newerFirst(_ a: Int64?, _ b: Int64?) -> Bool {
        (a ?? .min) > (b ?? .min)
    }

    static func durationText(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private static func episodeRow(_ ep: PodcastEpisode, detail: String?) -> CarPlayRow {
        let parts = [detail, durationText(ep.durationSeconds)].compactMap { $0 }.filter { !$0.isEmpty }
        return CarPlayRow(
            title: ep.title,
            detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
            imageUrl: nil,
            target: .episode(ep.id)
        )
    }
}
