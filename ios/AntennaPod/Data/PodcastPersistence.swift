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
