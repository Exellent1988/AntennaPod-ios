import Foundation

/// Android `prefEpisodeCleanup` ("Delete before auto download", default **Never**, global only).
/// Raw values are Android's `episode_cleanup_values`.
public enum EpisodeCleanup: Equatable, Hashable, Sendable {
    /// -3 `ExceptFavoriteCleanupAlgorithm`: any download that is not a favorite.
    case exceptFavorite
    /// -1 `APQueueCleanupAlgorithm`: not queued and not a favorite (played or not).
    case notInQueue
    /// 0 / 12 / 24 / 72 / 120 / 168 `APCleanupAlgorithm`: played, not queued, not a favorite,
    /// last played more than N hours ago (0 = "After finishing").
    case afterFinishing(hours: Int)
    /// -2 `APNullCleanupAlgorithm`: never deletes.
    case never

    public static let `default`: EpisodeCleanup = .never
    /// Android menu order.
    public static let options: [EpisodeCleanup] = [
        .exceptFavorite, .notInQueue, .afterFinishing(hours: 0), .afterFinishing(hours: 12),
        .afterFinishing(hours: 24), .afterFinishing(hours: 72), .afterFinishing(hours: 120),
        .afterFinishing(hours: 168), .never,
    ]

    public init(androidValue: Int) {
        switch androidValue {
        case -3: self = .exceptFavorite
        case -1: self = .notInQueue
        case -2: self = .never
        case let h where h >= 0: self = .afterFinishing(hours: h)
        default: self = .never
        }
    }

    public var androidValue: Int {
        switch self {
        case .exceptFavorite: return -3
        case .notInQueue: return -1
        case .never: return -2
        case .afterFinishing(let h): return h
        }
    }
}

/// One downloaded episode as seen by the cleanup.
public struct CleanupCandidate: Equatable, Sendable {
    public var id: String
    public var isPlayed: Bool
    public var isQueued: Bool
    public var isFavorite: Bool
    public var lastPlayedAt: Date?
    public var pubDate: Date?

    public init(id: String, isPlayed: Bool, isQueued: Bool, isFavorite: Bool, lastPlayedAt: Date?, pubDate: Date?) {
        self.id = id; self.isPlayed = isPlayed; self.isQueued = isQueued
        self.isFavorite = isFavorite; self.lastPlayedAt = lastPlayedAt; self.pubDate = pubDate
    }
}

/// Android `EpisodeCleanupAlgorithm` + `prefEpisodeCacheSize` ("Episode limit", default **20**,
/// global only). The limit counts all downloaded episodes; when auto-download needs room the
/// cleanup deletes eligible ones, and auto-download only fills what is left under the limit.
public enum EpisodeCleanupPolicy {
    public static let defaultCacheSize = 20
    /// Android `episode_cache_size_values` (nil = Unlimited, -1).
    public static let androidCacheSizeOptions: [Int?] = [5, 10, 25, 50, 100, 500, nil]

    public static func isEligible(_ c: CleanupCandidate, mode: EpisodeCleanup, now: Date) -> Bool {
        switch mode {
        case .never: return false
        case .exceptFavorite: return !c.isFavorite
        case .notInQueue: return !c.isQueued && !c.isFavorite
        case .afterFinishing(let hours):
            guard c.isPlayed, !c.isQueued, !c.isFavorite, let last = c.lastPlayedAt else { return false }
            return last < now.addingTimeInterval(-Double(hours) * 3600)
        }
    }

    /// Up to `count` eligible ids in Android's deletion order: oldest last-played first for
    /// "after finishing", oldest publication date first for the other two (no date = now).
    public static func victims(_ candidates: [CleanupCandidate], mode: EpisodeCleanup, count: Int, now: Date) -> [String] {
        guard count > 0 else { return [] }
        let eligible = candidates.filter { isEligible($0, mode: mode, now: now) }
        let key: (CleanupCandidate) -> Date
        if case .afterFinishing = mode { key = { $0.lastPlayedAt ?? now } } else { key = { $0.pubDate ?? now } }
        let sorted = eligible.enumerated().sorted { a, b in
            let l = key(a.element), r = key(b.element)
            return l != r ? l < r : a.offset < b.offset
        }.map(\.element.id)
        return Array(sorted.prefix(count))
    }

    /// Android `getNumEpisodesToCleanup`: how many to delete so `roomNeeded` more fit the limit.
    public static func numberToCleanUp(downloaded: Int, roomNeeded: Int, cacheSize: Int?) -> Int {
        guard roomNeeded >= 0, let cacheSize else { return 0 }
        return downloaded + roomNeeded >= cacheSize ? downloaded + roomNeeded - cacheSize : 0
    }

    /// Android `AutomaticDownloadAlgorithm`: how many of `wanted` new episodes to download after
    /// the cleanup deleted `deleted` of `downloaded` (never negative).
    public static func autoDownloadSpaceLeft(cacheSize: Int?, downloaded: Int, deleted: Int, wanted: Int) -> Int {
        guard let cacheSize, cacheSize < downloaded + wanted else { return max(0, wanted) }
        return max(0, min(wanted, cacheSize - (downloaded - deleted)))
    }

    /// Default for a missing episode-limit key: Android's 20 on new installs; existing installs
    /// keep the previous iOS default (unlimited) so nothing changes on update.
    public static func migratedCacheSize(keyPresent: Bool, hasExistingData: Bool) -> Int?? {
        if keyPresent { return nil }
        return .some(hasExistingData ? nil : defaultCacheSize)
    }

    /// Default for a missing cleanup key. Before this setting the iOS episode limit deleted any
    /// non-favorite, non-queued download; existing installs with a limit keep that (`notInQueue`).
    public static func migratedCleanup(keyPresent: Bool, existingCacheLimit: Int?) -> EpisodeCleanup? {
        if keyPresent { return nil }
        return existingCacheLimit != nil ? .notInQueue : .default
    }
}

/// Android `prefStreamOverDownload` ("Prefer streaming", default **off**, global only): list rows
/// show Stream instead of Download for episodes that are not downloaded. Android
/// `ItemActionButton.forItem`.
public enum EpisodeRowPrimaryAction: Equatable, Sendable {
    case play, cancelDownload, stream, download

    public static func forEpisode(isDownloaded: Bool, isDownloading: Bool, streamOverDownload: Bool) -> Self {
        if isDownloaded { return .play }
        if isDownloading { return .cancelDownload }
        return streamOverDownload ? .stream : .download
    }
}
