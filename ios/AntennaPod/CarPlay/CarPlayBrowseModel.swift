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
    /// `CPListItem.playbackProgress` (0…1).
    var progress: Double = 0
}

/// What a CarPlay list last showed; equal snapshots skip `updateSections`.
/// Playing id is normalized to rows actually in the list, so unrelated playback changes are no-ops.
struct CarPlayListSnapshot: Equatable {
    let rows: [CarPlayRow]
    let playingEpisodeId: String?

    init(rows: [CarPlayRow], playingEpisodeId: String?) {
        self.rows = rows
        let inList = rows.contains { $0.target == .episode(playingEpisodeId ?? "") }
        self.playingEpisodeId = (playingEpisodeId != nil && inList) ? playingEpisodeId : nil
    }
}

enum CarPlayBrowseModel {
    /// CarPlay list templates are capped by `CPListTemplate.maximumItemCount` (typically 12–100);
    /// we cap conservatively and let the template clamp further.
    static let maxRows = 100
    /// Coalesce bursts (refresh-all, bulk queue edits) into one CarPlay list update.
    static let refreshDebounceMs = 400

    static func subscriptionRows(_ feeds: [PodcastFeed]) -> [CarPlayRow] {
        feeds
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(maxRows)
            .map { CarPlayRow(title: $0.title, detail: $0.author, imageUrl: artworkURL($0.preferredDisplayArtworkURL, $0.imageUrl), target: .feed($0.id)) }
    }

    /// Newest first; episodes without a date go last.
    static func episodeRows(_ episodes: [PodcastEpisode], feedTitle: String? = nil, feedArtwork: String? = nil) -> [CarPlayRow] {
        episodes
            .sorted { newerFirst($0.pubDateEpochMs, $1.pubDateEpochMs) }
            .prefix(maxRows)
            .map { episodeRow($0, detail: feedTitle, feedArtwork: feedArtwork) }
    }

    /// Queue keeps user order.
    static func queueRows(_ queue: [PodcastEpisode], feedFor: (PodcastEpisode) -> PodcastFeed?) -> [CarPlayRow] {
        queue.prefix(maxRows).map { ep in
            let feed = feedFor(ep)
            return episodeRow(ep, detail: feed?.title, feedArtwork: feed.flatMap { artworkURL($0.preferredDisplayArtworkURL, $0.imageUrl) })
        }
    }

    static func downloadRows(
        feeds: [PodcastFeed],
        isDownloaded: (PodcastEpisode) -> Bool
    ) -> [CarPlayRow] {
        var seen = Set<String>()
        var pairs: [(PodcastEpisode, PodcastFeed)] = []
        for feed in feeds {
            for ep in feed.episodes where isDownloaded(ep) && seen.insert(ep.id).inserted {
                pairs.append((ep, feed))
            }
        }
        return pairs
            .sorted { newerFirst($0.0.pubDateEpochMs, $1.0.pubDateEpochMs) }
            .prefix(maxRows)
            .map { episodeRow($0.0, detail: $0.1.title, feedArtwork: artworkURL($0.1.preferredDisplayArtworkURL, $0.1.imageUrl)) }
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

    /// First non-blank http(s) URL among candidates (episode art, then feed art).
    static func artworkURL(_ candidates: String?...) -> String? {
        for c in candidates {
            guard let t = c?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
                  let scheme = URL(string: t)?.scheme?.lowercased(), scheme == "http" || scheme == "https"
            else { continue }
            return t
        }
        return nil
    }

    /// Episode row artwork, Android `FeedMedia.getMediaItem` order (item image → feed image), with
    /// Podcast Index item images preferred first. Same rule for Queue, Downloads, Currently playing.
    static func episodeArtworkURL(podcastImages: String?, itemImage: String?, feedDisplay: String?, feedImage: String?) -> String? {
        artworkURL(podcastImages, itemImage, feedDisplay, feedImage)
    }

    /// Pixel size to decode artwork at: CarPlay max item image size (points) × screen scale, ≥1.
    static func artworkPixelSize(maxPoints: Double, scale: Double) -> Int {
        max(1, Int((maxPoints * max(scale, 1)).rounded(.up)))
    }

    /// Distinct artwork URLs in row order (one fetch per URL).
    static func uniqueArtworkURLs(_ rows: [CarPlayRow]) -> [String] {
        var seen = Set<String>()
        return rows.compactMap(\.imageUrl).filter { seen.insert($0).inserted }
    }

    private static func episodeRow(_ ep: PodcastEpisode, detail: String?, feedArtwork: String? = nil) -> CarPlayRow {
        let parts = [detail, durationText(ep.durationSeconds)].compactMap { $0 }.filter { !$0.isEmpty }
        return CarPlayRow(
            title: ep.title,
            detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
            imageUrl: artworkURL(ep.preferredPodcastImagesArtworkURL, ep.imageUrl, feedArtwork),
            target: .episode(ep.id)
        )
    }
}
