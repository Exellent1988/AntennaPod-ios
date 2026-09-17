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
