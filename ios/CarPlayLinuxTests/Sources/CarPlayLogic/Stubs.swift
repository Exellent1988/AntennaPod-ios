// ===== STUBS — NOT APP CODE =====
// Minimal stand-ins for app types the real CarPlayListBuilder / CarPlayParity / CarPlayBrowseModel
// use. Signatures match ios/AntennaPod/Data/*.swift; behavior is simplified (see comments).
import Foundation

enum SubscriptionsSort: String, CaseIterable { case recentlyUpdated, alphabetical, byAuthor, byLanguage, mostUnplayed, recentlyRefreshed, leastRecentlyRefreshed }
enum FeedEpisodeSort: String, CaseIterable { case newestFirst, oldestFirst, shortestFirst, longestFirst, titleAscending, titleDescending }
enum FeedEpisodeFilter: String, CaseIterable { case all, unplayed, played }
enum DownloadsSort: String, CaseIterable { case newestFirst, oldestFirst, largestFirst, smallestFirst, titleAscending, titleDescending }
enum AllEpisodesFilter: String, CaseIterable { case all, unplayed, downloaded, favorites }
enum AllEpisodesSort: String, CaseIterable { case newestFirst, oldestFirst, shortestFirst, longestFirst, titleAscending, titleDescending }

struct PodcastEpisode: Hashable {
    var id: String
    var title: String
    var durationSeconds: Double = 600
    var pubDateEpochMs: Int64? = nil
    var imageUrl: String? = nil
    /// Stub: app derives this from podcast:images; tests set it directly.
    var preferredPodcastImagesArtworkURL: String? = nil
    var downloadUrl: String? = "https://media.example.com/ep.mp3"
    /// Same order as app `PodcastEpisode.artworkURL(feed:)`.
    func artworkURL(feed: PodcastFeed?) -> String? {
        [preferredPodcastImagesArtworkURL, imageUrl, feed?.preferredDisplayArtworkURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}

struct PodcastFeed: Hashable {
    var id = UUID()
    var title: String
    var feedUrl: String
    var author: String? = "Author"
    var imageUrl: String? = nil
    var lastRefreshedAtEpochMs: Int64? = nil
    var episodes: [PodcastEpisode]
    /// Stub: app prefers podcast:images, else trimmed imageUrl.
    var preferredDisplayArtworkURL: String? { imageUrl?.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct FeedSettings {
    var customTitle: String? = nil
    var episodeSort: FeedEpisodeSort? = nil
    func resolvedEpisodeSort(global: FeedEpisodeSort) -> FeedEpisodeSort { episodeSort ?? global }
}

struct DownloadedEpisode {
    var id: String
    var downloadedAtEpochMs: Int64? = nil
    var byteSize: Int64? = nil
    func knownByteSize() -> Int64? { byteSize }
}

@MainActor final class DownloadService {
    var downloads: [DownloadedEpisode] = []
    /// Stub: app checks a local file for the episode (keyed by episode id/URL).
    func isDownloaded(_ episode: PodcastEpisode) -> Bool { downloads.contains { $0.id == episode.id } }
}

@MainActor final class AppSettings {
    var subscriptionsSort: SubscriptionsSort = .alphabetical
    var feedEpisodeSort: FeedEpisodeSort = .newestFirst
    var feedEpisodeFilter: FeedEpisodeFilter = .all
    var downloadsSort: DownloadsSort = .newestFirst
    var allEpisodesFilter: AllEpisodesFilter = .all
    var allEpisodesSort: AllEpisodesSort = .newestFirst
}

@MainActor final class PodcastStore {
    var feeds: [PodcastFeed] = []
    var queue: [PodcastEpisode] = []
    var settingsByFeed: [UUID: FeedSettings] = [:]
    var played = Set<String>(), archived = Set<String>(), favorites = Set<String>()
    var positions: [String: Double] = [:]
    func feedSettings(for feedId: UUID) -> FeedSettings { settingsByFeed[feedId] ?? FeedSettings() }
    func displayTitle(for feed: PodcastFeed) -> String { feedSettings(for: feed.id).customTitle ?? feed.title }
    func isPlayed(_ id: String) -> Bool { played.contains(id) }
    func isArchived(_ id: String) -> Bool { archived.contains(id) }
    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    func positionSeconds(for id: String) -> Double { positions[id] ?? 0 }
    /// Stub: first feed containing the id (app uses an id→index map; same single-feed answer).
    func feed(containingEpisodeId id: String) -> PodcastFeed? { feeds.first { $0.episodes.contains { $0.id == id } } }
    func unplayedCountsByFeedId() -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: feeds.map { f in (f.id, f.episodes.filter { !played.contains($0.id) }.count) })
    }
}

#if os(Linux)
/// Stub: corelibs Foundation has no `String(localized:)`; return the development-language key.
extension String {
    init(localized key: String) { self = key }
}
#endif
