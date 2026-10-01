import Foundation

@MainActor
final class PodcastStore: ObservableObject {
    @Published var feeds: [PodcastFeed] = [] {
        didSet { PodcastPersistence.saveFeeds(feeds) }
    }
    @Published var queue: [PodcastEpisode] = [] {
        didSet { PodcastPersistence.saveQueue(queue) }
    }
    /// Episode id → position / played. Published so episode rows refresh.
    @Published var playbackStates: [String: EpisodePlaybackState] = [:] {
        didSet { PodcastPersistence.savePlaybackStates(playbackStates) }
    }
    @Published var isLoading = false
    @Published var lastError: String?

    private let repository = FeedRepository()

    init() {
        feeds = PodcastPersistence.loadFeeds()
        queue = PodcastPersistence.loadQueue()
        playbackStates = PodcastPersistence.loadPlaybackStates()
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
        for id in ids {
            playbackStates.removeValue(forKey: id)
        }
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

    // MARK: - Playback progress / played

    func playbackState(for episodeId: String) -> EpisodePlaybackState {
        playbackStates[episodeId] ?? .empty()
    }

    func isPlayed(_ episodeId: String) -> Bool {
        playbackStates[episodeId]?.isPlayed ?? false
    }

    func positionSeconds(for episodeId: String) -> Double {
        playbackStates[episodeId]?.positionSeconds ?? 0
    }

    /// Persist continuous progress while listening (does not flip played).
    func saveProgress(episodeId: String, positionSeconds: Double, durationSeconds: Double) {
        var state = playbackState(for: episodeId)
        state.positionSeconds = max(0, positionSeconds)
        if durationSeconds.isFinite, durationSeconds > 0 {
            state.durationSeconds = durationSeconds
        }
        state.updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        playbackStates[episodeId] = state
    }

    /// AntennaPod-like: mark played and reset position for a clean resume-from-start later.
    func markPlayed(_ episodeId: String, removeFromQueue: Bool = true) {
        var state = playbackState(for: episodeId)
        state.isPlayed = true
        state.positionSeconds = 0
        state.updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        playbackStates[episodeId] = state
        if removeFromQueue {
            queue.removeAll { $0.id == episodeId }
        }
    }

    func markUnplayed(_ episodeId: String) {
        var state = playbackState(for: episodeId)
        state.isPlayed = false
        state.updatedAtEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
        playbackStates[episodeId] = state
    }

    func togglePlayed(_ episodeId: String) {
        if isPlayed(episodeId) {
            markUnplayed(episodeId)
        } else {
            markPlayed(episodeId)
        }
    }

    /// Next queue item after `episodeId`, or the head of the queue if that id is gone.
    func nextQueueEpisode(after episodeId: String) -> PodcastEpisode? {
        if let index = queue.firstIndex(where: { $0.id == episodeId }) {
            let next = index + 1
            if next < queue.count {
                return queue[next]
            }
            return nil
        }
        return queue.first
    }
}
