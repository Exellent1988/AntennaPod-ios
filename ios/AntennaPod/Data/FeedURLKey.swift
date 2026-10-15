import Foundation

/// Equality key for podcast feed URLs (Android `UrlChecker.urlEquals`): scheme ignored
/// (http ≡ https), host case-insensitive, default port dropped, empty path segments
/// (double / trailing slashes) ignored, path case-insensitive, query compared exactly,
/// fragment ignored. Subscribe-link schemes (feed://, itpc://, pcast:, podcast://) and
/// surrounding whitespace are stripped first. Never use the key as a request URL.
enum FeedURLKey {
    nonisolated static func key(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        let lower = s.lowercased()
        for prefix in ["feed://", "itpc://", "pcast://", "podcast://", "podcasts://"] where lower.hasPrefix(prefix) {
            s = "http://" + s.dropFirst(prefix.count)
            break
        }
        let lowered = s.lowercased()
        if !lowered.hasPrefix("http"), lowered.hasPrefix("pcast:") || lowered.hasPrefix("feed:") {
            s = String(s.drop(while: { $0 != ":" }).dropFirst())
        }
        if !s.contains("://") { s = "http://" + s.drop(while: { $0 == "/" }) }
        guard let c = URLComponents(string: s), let host = c.host?.lowercased(), !host.isEmpty else {
            var fallback = lower
            while fallback.hasSuffix("/") { fallback.removeLast() }
            return fallback
        }
        var key = host
        if let port = c.port, !(port == 80 || port == 443) { key += ":\(port)" }
        let segments = c.percentEncodedPath.split(separator: "/").filter { !$0.isEmpty }.map { $0.lowercased() }
        if !segments.isEmpty { key += "/" + segments.joined(separator: "/") }
        if let q = c.percentEncodedQuery, !q.isEmpty { key += "?" + q }
        return key
    }
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
    /// stay. Episodes are unioned by id; the other URLs become alternates. Returns survivors in
    /// library order and the dropped id → survivor id map (to move per-feed side data).
    static func merge(_ feeds: [PodcastFeed]) -> (feeds: [PodcastFeed], merged: [UUID: UUID]) {
        var groups: [[Int]] = []
        var groupByKey: [String: Int] = [:]
        for (i, feed) in feeds.enumerated() {
            let keys = feed.urlKeys
            if let hit = keys.compactMap({ groupByKey[$0] }).min() {
                groups[hit].append(i)
                for k in keys { groupByKey[k] = hit }
            } else {
                for k in keys { groupByKey[k] = groups.count }
                groups.append([i])
            }
        }
        var result: [(Int, PodcastFeed)] = []
        var merged: [UUID: UUID] = [:]
        for members in groups {
            let ordered = members.map { feeds[$0] }
            let pick = ordered.firstIndex { $0.feedUrl.lowercased().hasPrefix("https://") && $0.loadError == nil }
                ?? ordered.firstIndex { $0.loadError == nil } ?? 0
            var survivor = ordered[pick]
            var episodes = survivor.episodes
            for (j, other) in ordered.enumerated() where j != pick {
                merged[other.id] = survivor.id
                for u in other.allUrls { survivor.addAlternateUrl(u) }
                episodes += other.episodes
            }
            survivor.episodes = PodcastFeed.uniqueEpisodes(episodes)
            result.append((members[pick], survivor))
        }
        return (result.sorted { $0.0 < $1.0 }.map(\.1), merged)
    }
}
