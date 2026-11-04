import Foundation

/// Local unsubscribes not yet confirmed by the gpodder server (Android
/// `SynchronizationQueueStorage` removed feeds). One entry per podcast: all its URLs (feed URL
/// first, then aliases). Matching uses `FeedURLEquality` keys over every URL.
public struct PendingSubscriptionRemovals: Codable, Equatable, Sendable {
    public private(set) var entries: [[String]]
    public init(entries: [[String]] = []) { self.entries = entries }

    public var isEmpty: Bool { entries.isEmpty }
    public var keys: Set<String> { FeedURLEquality.keys(entries.flatMap { $0 }) }
    public func contains(_ url: String) -> Bool { keys.contains(FeedURLEquality.key(url)) }

    /// Local unsubscribe: queue (merged with an entry sharing any key).
    public mutating func record(_ urls: [String]) {
        let clean = urls.filter { !FeedURLEquality.key($0).isEmpty }
        let k = FeedURLEquality.keys(clean)
        guard !k.isEmpty else { return }
        if let i = entries.firstIndex(where: { !FeedURLEquality.keys($0).isDisjoint(with: k) }) {
            // Distinct spellings are kept (the server compares URL strings).
            for u in clean where !entries[i].contains(u) { entries[i].append(u) }
        } else {
            entries.append(clean)
        }
    }

    /// Re-subscribe before the remove was uploaded (Android `enqueueFeedAdded`): cancel it.
    public mutating func cancel(_ urls: [String]) {
        let k = FeedURLEquality.keys(urls)
        entries.removeAll { !FeedURLEquality.keys($0).isDisjoint(with: k) }
    }

    /// Pulled `add` list without podcasts removed locally but not yet confirmed.
    public func filteringPull(_ add: [String]) -> [String] {
        let k = keys
        return add.filter { !k.contains(FeedURLEquality.key($0)) }
    }

    /// Like `filteringPull`, and remembers the server's own spellings of pending podcasts so
    /// the remove names exactly what the server stores (gpodder compares URL strings).
    public mutating func absorbingPull(_ add: [String]) -> [String] {
        let k = keys
        for u in add where k.contains(FeedURLEquality.key(u)) { record([u]) }
        return add.filter { !k.contains(FeedURLEquality.key($0)) }
    }

    /// Remove list for the push: every address the server is known to have for each podcast,
    /// else its feed URL. Spellings are sent as stored (trimmed only): the server matches the
    /// exact string it has, trailing slash included.
    public func urlsToRemove(remoteKeys: Set<String>) -> [String] {
        var out: [String] = []
        for urls in entries {
            var known = urls.filter { remoteKeys.contains(FeedURLEquality.key($0)) }
            if known.isEmpty, let first = urls.first { known = [first] }
            for u in known.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !out.contains(u) { out.append(u) }
        }
        return out
    }

    /// Successful push of `sent`: drop exactly those entries (later unsubscribes stay).
    public mutating func confirm(_ sent: PendingSubscriptionRemovals) {
        for e in sent.entries { if let i = entries.firstIndex(of: e) { entries.remove(at: i) } }
    }

    /// Server keys after the removes were confirmed.
    public func forgetting(_ remoteKeys: Set<String>) -> Set<String> { remoteKeys.subtracting(keys) }
}
