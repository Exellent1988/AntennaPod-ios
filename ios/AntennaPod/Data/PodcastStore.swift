import Foundation

@MainActor
final class PodcastStore: ObservableObject {
    @Published var feeds: [PodcastFeed] = [] {
        didSet { PodcastPersistence.saveFeeds(feeds) }
    }
    @Published var queue: [PodcastEpisode] = [] {
        didSet { PodcastPersistence.saveQueue(queue) }
    }
    @Published var isLoading = false
    @Published var lastError: String?

    private let repository = FeedRepository()

    init() {
        feeds = PodcastPersistence.loadFeeds()
        queue = PodcastPersistence.loadQueue()
    }

    func subscribe(feedUrl: String) async {
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            var feed = try await repository.fetchAndParse(feedUrl: feedUrl)
            feed.feedUrl = feedUrl
            if let index = feeds.firstIndex(where: { $0.feedUrl == feedUrl }) {
                feeds[index] = feed
            } else {
                feeds.append(feed)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func unsubscribe(_ feed: PodcastFeed) {
        feeds.removeAll { $0.id == feed.id }
        let ids = Set(feed.episodes.map(\.id))
        queue.removeAll { ids.contains($0.id) }
    }

    func refresh(_ feed: PodcastFeed) async {
        guard !feed.feedUrl.isEmpty else {
            return
        }
        await subscribe(feedUrl: feed.feedUrl)
    }

    func enqueue(_ episode: PodcastEpisode) {
        if !queue.contains(where: { $0.id == episode.id }) {
            queue.append(episode)
        }
    }

    func removeFromQueue(_ episode: PodcastEpisode) {
        queue.removeAll { $0.id == episode.id }
    }
}
