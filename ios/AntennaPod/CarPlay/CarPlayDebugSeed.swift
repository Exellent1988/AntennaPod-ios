#if DEBUG
import Foundation

/// Simulator-only seeding for CarPlay screenshots:
/// `-APDebugSeedFeeds "https://a/feed.xml|https://b/feed.xml"` subscribes (skips existing), queues the
/// newest episodes, downloads one, and loads the first queued episode paused (Currently playing).
@MainActor
enum CarPlayDebugSeed {
    static func runIfRequested(store: PodcastStore, playback: PlaybackService, downloads: DownloadService) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-APDebugSeedDuplicateFeeds") { seedDuplicateFeeds(store: store) }
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

    /// `-APDebugSeedDuplicateFeeds`: offline twin feeds (http / https / trailing slash) sharing episode
    /// GUIDs plus a feed with no episodes (failed parse), all queued, for the beta duplicate-URL crash.
    static func seedDuplicateFeeds(store: PodcastStore) {
        guard !store.feeds.contains(where: { $0.title.hasPrefix("Dup seed") }) else { return }
        func ep(_ g: String, _ t: String, _ m: String) -> PodcastEpisode {
            PodcastEpisode(id: g, title: t, downloadUrl: m, mimeType: "audio/mpeg", durationSeconds: 600)
        }
        func feed(_ url: String, _ title: String, _ eps: [PodcastEpisode]) -> PodcastFeed {
            PodcastFeed(id: UUID(), title: title, feedUrl: url, siteLink: nil, imageUrl: nil, descriptionText: "",
                        author: "Debug", language: nil, fundingUrl: nil, fundingLabel: nil, categories: [],
                        isLocked: false, lockedOwner: nil, podcastGuid: nil, episodes: eps)
        }
        let a = ep("dup-seed-1", "Dup episode 1", "https://dup.invalid/1.mp3")
        let b = ep("dup-seed-2", "Dup episode 2", "https://dup.invalid/2.mp3")
        let twins = [
            feed("http://dup.invalid/feed", "Dup seed http", [a, b]),
            feed("https://dup.invalid/feed", "Dup seed https", [a, a]),
            feed("https://dup.invalid/feed/", "Dup seed slash", [b]),
            feed("https://dup.invalid/broken", "Dup seed parse failed", []),
        ]
        store.feeds.append(contentsOf: twins)
        for e in [a, b, a] { store.enqueue(e) }
    }
}
#endif
