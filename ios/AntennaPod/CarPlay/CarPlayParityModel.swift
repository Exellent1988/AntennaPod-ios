import Foundation

/// Flattened, framework-free episode facts for CarPlay list building (mirrors Android Auto
/// `PlaybackService.loadChildrenSynchronous`). Built from stores in the scene delegate; pure here.
struct CarPlayEpisodeInfo: Equatable {
    var id: String
    var title: String
    var feedTitle: String
    var artwork: String?
    var pubDateEpochMs: Int64?
    var durationSeconds: Double
    var positionSeconds: Double = 0
    var isPlayed = false
    var isArchived = false
    var isFavorite = false
    var isDownloaded = false
    var downloadedAtEpochMs: Int64?
    var byteSize: Int64?
}

/// Root tabs in Android Auto order (Queue, Downloads, Episodes, Subscriptions). CarPlay audio apps
/// allow at most 4 tabs, so Android's "Currently playing" root row becomes a section atop Queue.
enum CarPlayTab: String, CaseIterable {
    case queue, downloads, episodes, subscriptions
}

enum CarPlayParity {
    /// Android `MAX_ANDROID_AUTO_EPISODES_PER_FEED`.
    static let androidMaxItems = 100

    /// Effective list cap: Android's 100, further clamped by `CPListTemplate.maximumItemCount`.
    static func itemLimit(templateMax: Int) -> Int {
        templateMax > 0 ? min(androidMaxItems, templateMax) : androidMaxItems
    }

    /// Fraction for `CPListItem.playbackProgress`: 0 when unstarted/unknown, 1 when played.
    static func progress(_ e: CarPlayEpisodeInfo) -> Double {
        if e.isPlayed { return 1 }
        guard e.durationSeconds.isFinite, e.durationSeconds > 0, e.positionSeconds > 0 else { return 0 }
        return min(1, max(0, e.positionSeconds / e.durationSeconds))
    }

    /// "In progress" = started, not played (Android "playback in progress").
    static func isInProgress(_ e: CarPlayEpisodeInfo) -> Bool {
        !e.isPlayed && e.positionSeconds > 0
    }

    /// Detail line: feed title · remaining (in progress) or duration.
    static func detail(_ e: CarPlayEpisodeInfo, showFeed: Bool = true) -> String? {
        var parts: [String] = []
        if showFeed, !e.feedTitle.isEmpty { parts.append(e.feedTitle) }
        if isInProgress(e), e.durationSeconds > e.positionSeconds,
           let left = CarPlayBrowseModel.durationText(e.durationSeconds - e.positionSeconds) {
            parts.append(String(localized: "\(left) left"))
        } else if let d = CarPlayBrowseModel.durationText(e.durationSeconds) {
            parts.append(d)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Up Next: queue items after the current episode; whole queue when current is not queued.
    static func upNext(queueIds: [String], currentId: String?) -> [String] {
        guard let currentId, let idx = queueIds.firstIndex(of: currentId) else { return queueIds }
        return Array(queueIds[(idx + 1)...])
    }

    // MARK: Episodes tab — All Episodes filter + sort (Android: getPrefFilterAllEpisodes / getAllEpisodesSortOrder)

    static func episodes(_ all: [CarPlayEpisodeInfo], filter: AllEpisodesFilter, sort: AllEpisodesSort, limit: Int) -> [CarPlayEpisodeInfo] {
        let filtered: [CarPlayEpisodeInfo]
        switch filter {
        case .all: filtered = all
        case .unplayed: filtered = all.filter { !$0.isPlayed && !$0.isArchived }
        case .downloaded: filtered = all.filter(\.isDownloaded)
        case .favorites: filtered = all.filter(\.isFavorite)
        }
        return Array(sorted(filtered, by: sort).prefix(limit))
    }

    static func sorted(_ list: [CarPlayEpisodeInfo], by sort: AllEpisodesSort) -> [CarPlayEpisodeInfo] {
        let tie: (CarPlayEpisodeInfo, CarPlayEpisodeInfo) -> Bool = { $0.id < $1.id }
        func known(_ a: Double) -> Double? { a.isFinite && a > 0 ? a : nil }
        return list.sorted { a, b in
            switch sort {
            case .newestFirst:
                return a.pubDateEpochMs == b.pubDateEpochMs ? tie(a, b) : CarPlayBrowseModel.newerFirst(a.pubDateEpochMs, b.pubDateEpochMs)
            case .oldestFirst:
                return a.pubDateEpochMs == b.pubDateEpochMs ? tie(a, b) : (a.pubDateEpochMs ?? .max) < (b.pubDateEpochMs ?? .max)
            case .shortestFirst, .longestFirst:
                switch (known(a.durationSeconds), known(b.durationSeconds)) {
                case let (x?, y?) where x != y: return sort == .shortestFirst ? x < y : x > y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return tie(a, b)
                }
            case .titleAscending, .titleDescending:
                return titleOrder(a.title, b.title, ascending: sort == .titleAscending) ?? tie(a, b)
            }
        }
    }

    // MARK: Downloads tab — Downloads sort (Android: getDownloadsSortedOrder)

    static func downloads(_ all: [CarPlayEpisodeInfo], sort: DownloadsSort, limit: Int) -> [CarPlayEpisodeInfo] {
        let tie: (CarPlayEpisodeInfo, CarPlayEpisodeInfo) -> Bool = { $0.id < $1.id }
        let key: (CarPlayEpisodeInfo) -> Int64? = { $0.downloadedAtEpochMs ?? $0.pubDateEpochMs }
        let sorted = all.filter(\.isDownloaded).sorted { a, b in
            switch sort {
            case .newestFirst: return key(a) == key(b) ? tie(a, b) : CarPlayBrowseModel.newerFirst(key(a), key(b))
            case .oldestFirst: return key(a) == key(b) ? tie(a, b) : (key(a) ?? .max) < (key(b) ?? .max)
            case .largestFirst, .smallestFirst:
                switch (a.byteSize, b.byteSize) {
                case let (x?, y?) where x != y: return sort == .smallestFirst ? x < y : x > y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return tie(a, b)
                }
            case .titleAscending, .titleDescending:
                return titleOrder(a.title, b.title, ascending: sort == .titleAscending) ?? tie(a, b)
            }
        }
        return Array(sorted.prefix(limit))
    }

    // MARK: Subscriptions — subset of SubscriptionsSort; unsupported cases fall back to alphabetical.

    struct FeedInfo: Equatable {
        var id: UUID
        var title: String
        var author: String?
        var unplayedCount: Int
        var lastRefreshedEpochMs: Int64?
    }

    static func feeds(_ all: [FeedInfo], sort: SubscriptionsSort, limit: Int) -> [FeedInfo] {
        let alpha: (FeedInfo, FeedInfo) -> Bool = {
            titleOrder($0.title, $1.title, ascending: true) ?? ($0.id.uuidString < $1.id.uuidString)
        }
        let sorted = all.sorted { a, b in
            switch sort {
            case .byAuthor:
                let x = a.author ?? "", y = b.author ?? ""
                return titleOrder(x, y, ascending: true) ?? alpha(a, b)
            case .mostUnplayed:
                return a.unplayedCount == b.unplayedCount ? alpha(a, b) : a.unplayedCount > b.unplayedCount
            case .recentlyRefreshed, .leastRecentlyRefreshed:
                switch (a.lastRefreshedEpochMs, b.lastRefreshedEpochMs) {
                case let (x?, y?) where x != y: return sort == .recentlyRefreshed ? x > y : x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return alpha(a, b)
                }
            default:
                return alpha(a, b)
            }
        }
        return Array(sorted.prefix(limit))
    }

    /// Case-insensitive title order; empty last. `nil` when equal (caller tiebreaks).
    static func titleOrder(_ a: String, _ b: String, ascending: Bool) -> Bool? {
        let x = a.trimmingCharacters(in: .whitespaces), y = b.trimmingCharacters(in: .whitespaces)
        if x.isEmpty != y.isEmpty { return !x.isEmpty }
        let r = x.localizedCaseInsensitiveCompare(y)
        if r == .orderedSame { return nil }
        return ascending ? r == .orderedAscending : r == .orderedDescending
    }
}
