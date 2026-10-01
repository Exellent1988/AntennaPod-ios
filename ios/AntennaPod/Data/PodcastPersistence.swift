import Foundation

enum PodcastPersistence {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AntennaPod", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var feedsURL: URL { directory.appendingPathComponent("feeds.json") }
    private static var queueURL: URL { directory.appendingPathComponent("queue.json") }
    private static var playbackURL: URL { directory.appendingPathComponent("playback.json") }
    private static var downloadsURL: URL { directory.appendingPathComponent("downloads.json") }
    private static var pendingDownloadsURL: URL { directory.appendingPathComponent("pending-downloads.json") }
    private static var feedSettingsURL: URL { directory.appendingPathComponent("feed-settings.json") }
    private static var favoritesURL: URL { directory.appendingPathComponent("favorites.json") }
    private static var archivedURL: URL { directory.appendingPathComponent("archived.json") }
    private static var feedTagsURL: URL { directory.appendingPathComponent("feed-tags.json") }
    private static var downloadErrorsURL: URL { directory.appendingPathComponent("download-errors.json") }
    private static var localFolderBookmarksURL: URL { directory.appendingPathComponent("local-folder-bookmarks.json") }

    /// Application Support/AntennaPod directory (created if needed).
    static var applicationSupportDirectory: URL { directory }

    /// Absolute URL for a persistence file name under Application Support/AntennaPod.
    static func fileURL(_ fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Replace a persistence file atomically (used by data backup import).
    static func writeFile(name: String, data: Data) throws {
        let url = fileURL(name)
        try data.write(to: url, options: .atomic)
    }

    static func loadFeeds() -> [PodcastFeed] {
        decode(feedsURL) ?? []
    }

    static func saveFeeds(_ feeds: [PodcastFeed]) {
        encode(feeds, to: feedsURL)
    }

    static func loadQueue() -> [PodcastEpisode] {
        decode(queueURL) ?? []
    }

    static func saveQueue(_ queue: [PodcastEpisode]) {
        encode(queue, to: queueURL)
    }

    /// Map of episode id → playback state.
    static func loadPlaybackStates() -> [String: EpisodePlaybackState] {
        decode(playbackURL) ?? [:]
    }

    static func savePlaybackStates(_ states: [String: EpisodePlaybackState]) {
        encode(states, to: playbackURL)
    }

    /// Completed offline downloads (episode metadata + file name under Documents/downloads).
    static func loadDownloadedEpisodes() -> [DownloadedEpisode] {
        decode(downloadsURL) ?? []
    }

    static func saveDownloadedEpisodes(_ items: [DownloadedEpisode]) {
        encode(items, to: downloadsURL)
    }

    /// In-flight background URLSession task ↔ episode mappings (survive relaunch).
    static func loadPendingDownloads() -> [PendingDownloadMapping] {
        decode(pendingDownloadsURL) ?? []
    }

    static func savePendingDownloads(_ items: [PendingDownloadMapping]) {
        encode(items, to: pendingDownloadsURL)
    }

    /// Per-feed overrides keyed by `PodcastFeed.id` (side map; refresh does not wipe them).
    static func loadFeedSettings() -> [UUID: FeedSettings] {
        let raw: [String: FeedSettings] = decode(feedSettingsURL) ?? [:]
        var out: [UUID: FeedSettings] = [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key) else { continue }
            out[id] = value
        }
        return out
    }

    static func saveFeedSettings(_ map: [UUID: FeedSettings]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
        encode(raw, to: feedSettingsURL)
    }

    /// Episode id → favorited-at epoch ms (side map; survives playback.json clears).
    static func loadFavorites() -> [String: Int64] {
        decode(favoritesURL) ?? [:]
    }

    static func saveFavorites(_ map: [String: Int64]) {
        encode(map, to: favoritesURL)
    }

    /// Episode id → archived-at epoch ms (side map; archived ≠ played).
    static func loadArchived() -> [String: Int64] {
        decode(archivedURL) ?? [:]
    }

    static func saveArchived(_ map: [String: Int64]) {
        encode(map, to: archivedURL)
    }

    /// Per-feed tag names keyed by `PodcastFeed.id` (side map; empty arrays omitted).
    static func loadFeedTags() -> [UUID: [String]] {
        let raw: [String: [String]] = decode(feedTagsURL) ?? [:]
        var out: [UUID: [String]] = [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key) else { continue }
            let tags = FeedTags.uniqueSorted(value)
            if !tags.isEmpty {
                out[id] = tags
            }
        }
        return out
    }

    static func saveFeedTags(_ map: [UUID: [String]]) {
        let cleaned = map.compactMap { key, value -> (String, [String])? in
            let tags = FeedTags.uniqueSorted(value)
            guard !tags.isEmpty else { return nil }
            return (key.uuidString, tags)
        }
        let raw = Dictionary(uniqueKeysWithValues: cleaned)
        encode(raw, to: feedTagsURL)
    }

    /// Ring buffer of recent download failures (newest first; capped by caller).
    static func loadDownloadErrors() -> [DownloadErrorEntry] {
        decode(downloadErrorsURL) ?? []
    }

    static func saveDownloadErrors(_ items: [DownloadErrorEntry]) {
        encode(items, to: downloadErrorsURL)
    }

    /// Feed id (uuid string) → base64 security-scoped bookmark for local folder feeds.
    static func loadLocalFolderBookmarks() -> [String: String] {
        decode(localFolderBookmarksURL) ?? [:]
    }

    static func saveLocalFolderBookmarks(_ map: [String: String]) {
        encode(map, to: localFolderBookmarksURL)
    }

    private static func decode<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
