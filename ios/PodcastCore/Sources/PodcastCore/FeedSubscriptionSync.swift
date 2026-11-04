import Foundation

/// Feed URL equality (Android `UrlChecker.urlEquals`): scheme ignored (http ≡ https), host
/// case-insensitive, default port dropped, empty path segments (double / trailing slashes)
/// ignored, path case-insensitive, query compared exactly, fragment ignored. Subscribe-link
/// schemes (feed://, itpc://, pcast:, podcast://) and surrounding whitespace are stripped first.
/// The key is for comparison only; never use it as a request URL.
public enum FeedURLEquality {
    public static func key(_ raw: String) -> String {
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

    /// URL to fetch or upload: trim, drop trailing slashes, lowercase the scheme only (path,
    /// host and query keep their case so case-sensitive paths and tokens survive sync).
    public static func requestURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if let sep = s.range(of: "://") {
            s = s[..<sep.lowerBound].lowercased() + s[sep.lowerBound...]
        }
        return s
    }

    /// True for http:// and https:// URLs (the key has no scheme, so check the real URL).
    public static func isHTTP(_ raw: String) -> Bool {
        let l = requestURL(raw).lowercased()
        return l.hasPrefix("http://") || l.hasPrefix("https://")
    }

    /// Non-empty keys for a set of URLs (one podcast's feed URL plus its aliases).
    public static func keys(_ urls: [String]) -> Set<String> {
        Set(urls.map(key)).subtracting([""])
    }
}

/// Pure gpodder subscription diff (no I/O). A local podcast is described by all of its URLs
/// (feed URL first, then redirect / pre-redirect aliases).
public enum SubscriptionSyncPlan {
    /// Remote URLs to subscribe: http(s) only, not already local under any alias, one per
    /// equality key (first spelling and remote order kept, as `requestURL`).
    public static func urlsToImport(remote: [String], localFeedURLs: [String]) -> [String] {
        var seen = FeedURLEquality.keys(localFeedURLs)
        var result: [String] = []
        for raw in remote {
            let url = FeedURLEquality.requestURL(raw)
            let key = FeedURLEquality.key(url)
            guard !key.isEmpty, FeedURLEquality.isHTTP(url), seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }

    /// Distinct http(s) podcasts on the server (by equality key).
    public static func distinctRemoteCount(_ remote: [String]) -> Int {
        Set(remote.filter(FeedURLEquality.isHTTP).map(FeedURLEquality.key)).subtracting([""]).count
    }

    /// Local URLs to unsubscribe for a server `remove` list (incremental sync only). A URL that
    /// is also in `add` is kept (re-subscribed elsewhere in the same window).
    public static func feedsToUnsubscribe(remove: [String], add: [String], localFeedURLs: [String]) -> [String] {
        let removeKeys = FeedURLEquality.keys(remove).subtracting(FeedURLEquality.keys(add))
        return localFeedURLs.filter { removeKeys.contains(FeedURLEquality.key($0)) }
    }

    /// Indexes of local podcasts whose any URL the server removed (incremental sync). A podcast
    /// the same window also adds under another of its URLs (feed URL changed / redirect rewrite:
    /// server removes the old address and adds the new one) is kept.
    public static func podcastsToUnsubscribe(remove: [String], add: [String], localPodcasts: [[String]]) -> [Int] {
        let addKeys = FeedURLEquality.keys(add)
        let removeKeys = FeedURLEquality.keys(remove).subtracting(addKeys)
        return localPodcasts.indices.filter {
            let keys = FeedURLEquality.keys(localPodcasts[$0])
            return !keys.isDisjoint(with: removeKeys) && keys.isDisjoint(with: addKeys)
        }
    }

    /// Feed URLs to upload: http(s) podcasts the server knows under none of their URLs, one per
    /// podcast (its feed URL, as `requestURL`). A podcast the server has under another address
    /// (pre-redirect URL, http/https variant) is not uploaded again; that is what filled
    /// accounts with duplicates that came back after a reinstall.
    public static func urlsToUpload(localPodcasts: [[String]], remoteKeys: Set<String>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for urls in localPodcasts {
            guard let feedURL = urls.first else { continue }
            let url = FeedURLEquality.requestURL(feedURL)
            let key = FeedURLEquality.key(url)
            guard !key.isEmpty, FeedURLEquality.isHTTP(url) else { continue }
            let all = FeedURLEquality.keys(urls)
            guard all.isDisjoint(with: remoteKeys), all.isDisjoint(with: seen) else { continue }
            seen.formUnion(all)
            result.append(url)
        }
        return result
    }
}

/// Groups library entries that are the same podcast (any shared URL key, transitively).
public enum FeedDuplicateGrouping {
    public struct Entry: Equatable, Sendable {
        public var urls: [String]
        public var loaded: Bool
        public init(urls: [String], loaded: Bool) { self.urls = urls; self.loaded = loaded }
    }

    /// Groups of entry indexes in first-appearance order; within a group, indexes ascending.
    public static func groups(_ entries: [[String]]) -> [[Int]] {
        var parent = Array(entries.indices)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        var owner: [String: Int] = [:]
        for (i, urls) in entries.enumerated() {
            for k in FeedURLEquality.keys(urls) {
                if let j = owner[k] {
                    let a = find(i), b = find(j)
                    if a != b { parent[max(a, b)] = min(a, b) }
                } else {
                    owner[k] = i
                }
            }
        }
        var byRoot: [Int: [Int]] = [:]
        var order: [Int] = []
        for i in entries.indices {
            let r = find(i)
            if byRoot[r] == nil { order.append(r) }
            byRoot[r, default: []].append(i)
        }
        return order.map { byRoot[$0]! }
    }

    /// Survivor index for a group: the first loaded https entry, else the first loaded, else the first.
    public static func survivor(_ group: [Int], entries: [Entry]) -> Int {
        group.first { entries[$0].loaded && (entries[$0].urls.first?.lowercased().hasPrefix("https://") ?? false) }
            ?? group.first { entries[$0].loaded } ?? group[0]
    }
}
