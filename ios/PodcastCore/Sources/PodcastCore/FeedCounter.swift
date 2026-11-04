import Foundation

/// Android `FeedCounter` (model/.../feed/FeedCounter.java) for the Subscriptions / drawer per-feed counter,
/// with the exact row rules of `PodDBAdapter.getFeedCounters` (storage/database/.../PodDBAdapter.java:1339):
/// - SHOW_NEW: `read = NEW` (iOS: still in the Inbox, i.e. not played and not archived)
/// - SHOW_UNPLAYED: `read = NEW OR read = UNPLAYED` (iOS: not played; archived counts)
/// - SHOW_DOWNLOADED: `downloadDate > 0 OR` the feed is a local folder
/// - SHOW_DOWNLOADED_UNPLAYED: unplayed AND (downloaded OR local folder)
/// - SHOW_NONE: no counter
public enum FeedCounterKind: String, CaseIterable, Codable, Sendable {
    case none
    case new
    case unplayed
    case downloaded
    case downloadedUnplayed
}

/// Per-episode facts the counter needs (no app types, so this stays testable on Linux).
public struct FeedCounterEpisode: Equatable, Sendable {
    public var isPlayed: Bool
    public var isArchived: Bool
    public var isDownloaded: Bool

    public init(isPlayed: Bool, isArchived: Bool, isDownloaded: Bool) {
        self.isPlayed = isPlayed
        self.isArchived = isArchived
        self.isDownloaded = isDownloaded
    }
}

public enum FeedCounterRule {
    /// Counter value for one feed.
    public static func count(_ kind: FeedCounterKind, episodes: [FeedCounterEpisode], isLocalFolderFeed: Bool) -> Int {
        switch kind {
        case .none:
            return 0
        case .new:
            return episodes.filter { !$0.isPlayed && !$0.isArchived }.count
        case .unplayed:
            return episodes.filter { !$0.isPlayed }.count
        case .downloaded:
            return episodes.filter { $0.isDownloaded || isLocalFolderFeed }.count
        case .downloadedUnplayed:
            return episodes.filter { !$0.isPlayed && ($0.isDownloaded || isLocalFolderFeed) }.count
        }
    }
}
