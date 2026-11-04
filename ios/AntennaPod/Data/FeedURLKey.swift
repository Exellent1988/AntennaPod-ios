import Foundation
import PodcastCore

/// Equality key for podcast feed URLs (Android `UrlChecker.urlEquals`): scheme ignored
/// (http ≡ https), host case-insensitive, default port dropped, empty path segments
/// (double / trailing slashes) ignored, path case-insensitive, query compared exactly,
/// fragment ignored. Subscribe-link schemes (feed://, itpc://, pcast:, podcast://) and
/// surrounding whitespace are stripped first. Never use the key as a request URL.
enum FeedURLKey {
    nonisolated static func key(_ raw: String) -> String { FeedURLEquality.key(raw) }
}

extension PodcastFeed {
    /// `feedUrl` plus every alternate URL (pre-redirect / final), as equality keys.
    var urlKeys: Set<String> {
        var keys: Set<String> = [FeedURLKey.key(feedUrl)]
        for u in alternateUrls ?? [] { keys.insert(FeedURLKey.key(u)) }
        keys.remove("")
        return keys
    }

    /// `feedUrl` plus alternates as raw URLs (for gpodder matching).
    var allUrls: [String] { [feedUrl] + (alternateUrls ?? []) }

    /// Record `url` as another address of this podcast (no-op when already known).
    mutating func addAlternateUrl(_ url: String) {
        let k = FeedURLKey.key(url)
        guard !k.isEmpty, !urlKeys.contains(k) else { return }
        alternateUrls = (alternateUrls ?? []) + [url]
    }

    /// Episodes with unique ids, first occurrence kept. Some feeds repeat a guid; duplicate
    /// ids break SwiftUI list identity (rows, swipe actions, the episode pager).
    static func uniqueEpisodes(_ episodes: [PodcastEpisode]) -> [PodcastEpisode] {
        var seen = Set<String>()
        return episodes.filter { seen.insert($0.id).inserted }
    }
}

enum FeedLibraryDedupe {
    /// Merge feeds that are the same podcast (shared URL key). The survivor is the first
    /// loaded https entry (else the first loaded, else the first); its id, settings and title
    /// stay. Episodes are unioned by id; the other URLs become alternates. The survivor keeps its
    /// own `lastRefreshError` (its address is the one refreshed from now on); a dropped duplicate's
    /// refresh error is not carried over. Returns survivors in
    /// library order and the dropped id → survivor id map (to move per-feed side data).
    static func merge(_ feeds: [PodcastFeed]) -> (feeds: [PodcastFeed], merged: [UUID: UUID]) {
        let entries = feeds.map { FeedDuplicateGrouping.Entry(urls: $0.allUrls, loaded: $0.loadError == nil) }
        var result: [(Int, PodcastFeed)] = []
        var merged: [UUID: UUID] = [:]
        for group in FeedDuplicateGrouping.groups(entries.map(\.urls)) {
            let pick = FeedDuplicateGrouping.survivor(group, entries: entries)
            var survivor = feeds[pick]
            var episodes = survivor.episodes
            for i in group where i != pick {
                merged[feeds[i].id] = survivor.id
                for u in feeds[i].allUrls { survivor.addAlternateUrl(u) }
                episodes += feeds[i].episodes
            }
            survivor.episodes = PodcastFeed.uniqueEpisodes(episodes)
            result.append((pick, survivor))
        }
        return (result.sorted { $0.0 < $1.0 }.map(\.1), merged)
    }
}
