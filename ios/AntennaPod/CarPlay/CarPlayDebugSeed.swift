#if DEBUG
import Foundation

/// Simulator-only seeding for CarPlay screenshots:
/// `-APDebugSeedFeeds "https://a/feed.xml|https://b/feed.xml"` subscribes (skips existing), queues the
/// newest episodes, downloads one, and loads the first queued episode paused (Currently playing).
@MainActor
enum CarPlayDebugSeed {
    static func runIfRequested(store: PodcastStore, playback: PlaybackService, downloads: DownloadService) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-APDebugSeedFeeds"), i + 1 < args.count else { return }
        let urls = args[i + 1].split(separator: "|").map(String.init)
        Task { @MainActor in
            for url in urls where !store.feeds.contains(where: { $0.feedUrl == url }) {
                _ = await store.subscribe(feedUrl: url)
            }
            guard store.queue.isEmpty else { return }
            for (n, feed) in store.feeds.enumerated() {
                let newest = feed.episodes.sorted { ($0.pubDateEpochMs ?? 0) > ($1.pubDateEpochMs ?? 0) }
                for ep in newest.prefix(n == 0 ? 3 : 2) { store.enqueue(ep) }
            }
            if let second = store.queue.dropFirst().first { await downloads.download(second) }
            if let first = store.queue.first, playback.play(episode: first) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if playback.isPlaying { playback.togglePlayPause() }
            }
        }
    }
}
#endif
