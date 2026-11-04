import Foundation

/// Subscriptions list order, shared by the Subscriptions screen and the iPad sidebar.
/// Android: the drawer and the subscriptions screen both use UserPreferences.getFeedOrder()
/// (DBReader.getNavDrawerData feedOrder comparator, DBReader.java:690+), so both follow one setting.
/// Moved verbatim from SubscriptionsView.sortedFeeds (behaviour unchanged).
enum SubscriptionsFeedOrder {
    @MainActor
    static func sorted(_ feeds: [PodcastFeed], by sort: SubscriptionsSort, store: PodcastStore) -> [PodcastFeed] {
        let sorted: [PodcastFeed]
        switch sort {
        case .recentlyUpdated:
            sorted = feeds.sorted { lhs, rhs in
                let l = lhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
                let r = rhs.episodes.compactMap(\.pubDateEpochMs).max() ?? Int64.min
                if l != r { return l > r }
                return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
            }
        case .alphabetical:
            sorted = feeds.sorted {
                store.displayTitle(for: $0).localizedCaseInsensitiveCompare(store.displayTitle(for: $1)) == .orderedAscending
            }
        case .byAuthor:
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.displayAuthor, rhs.displayAuthor) {
                case (nil, nil):
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                }
            }
        case .byLanguage:
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.displayLanguage, rhs.displayLanguage) {
                case (nil, nil):
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    let cmp = l.localizedCaseInsensitiveCompare(r)
                    if cmp != .orderedSame { return cmp == .orderedAscending }
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                }
            }
        case .mostUnplayed:
            // Same definition as row badges / Inbox (`!isPlayed && !isArchived`; missing = 0).
            let counts = store.unplayedCountsByFeedId()
            sorted = feeds.sorted { lhs, rhs in
                let l = counts[lhs.id] ?? 0
                let r = counts[rhs.id] ?? 0
                if l != r { return l > r }
                return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
            }
        case .recentlyRefreshed:
            // Newest successful network stamp first; nil / local-folder last (never invent).
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.lastRefreshedAtEpochMs, rhs.lastRefreshedAtEpochMs) {
                case (nil, nil):
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    if l != r { return l > r }
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                }
            }
        case .leastRecentlyRefreshed:
            // Oldest successful network stamp first; nil / local-folder last (never invent).
            sorted = feeds.sorted { lhs, rhs in
                switch (lhs.lastRefreshedAtEpochMs, rhs.lastRefreshedAtEpochMs) {
                case (nil, nil):
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (l?, r?):
                    if l != r { return l < r }
                    return store.displayTitle(for: lhs).localizedCaseInsensitiveCompare(store.displayTitle(for: rhs)) == .orderedAscending
                }
            }
        }
        // Invisible pin partition on every existing sort (not a new Picker case).
        let pinned = sorted.filter { store.isPinned(feedId: $0.id) }
        let unpinned = sorted.filter { !store.isPinned(feedId: $0.id) }
        return pinned + unpinned
    }
}
