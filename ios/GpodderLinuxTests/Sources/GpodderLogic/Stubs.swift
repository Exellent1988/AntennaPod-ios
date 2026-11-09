// STUBS for the Linux harness. Each mirrors the app declaration it replaces.
import Foundation
import PodcastCore

/// AntennaPod/Data/FeedURLKey.swift (same one-liner; the file's PodcastFeed extension is not needed).
enum FeedURLKey { static func key(_ raw: String) -> String { FeedURLEquality.key(raw) } }

/// AntennaPod/Data/GpodderSyncService.swift: the two URL helpers GpodderSyncLogic calls (same bodies).
enum GpodderSyncService {
    static func syncFeedURL(_ raw: String) -> String { FeedURLEquality.requestURL(raw) }
    static func normalizeFeedURL(_ raw: String) -> String { FeedURLKey.key(raw) }
}

/// AntennaPod/Data/PodcastModels.swift EpisodePlaybackState: the fields gpodder sync reads/writes.
struct EpisodePlaybackState: Hashable, Codable {
    var positionSeconds: Double
    var durationSeconds: Double
    var isPlayed: Bool
    var updatedAtEpochMs: Int64
    var lastPlayedAtEpochMs: Int64? = nil
    var playStartedSeconds: Double? = nil
    var playActionPositionSeconds: Double? = nil
}
