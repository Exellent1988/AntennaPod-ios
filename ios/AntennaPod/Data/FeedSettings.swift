import Foundation

/// Tri-state override for per-subscription preferences (Android-style Use global / Always / Never).
enum PerFeedOverride: String, CaseIterable, Identifiable, Codable, Hashable {
    case useGlobal
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .useGlobal: return "Use global"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

/// Per-subscription overrides (keyed by `PodcastFeed.id` in a side map).
struct FeedSettings: Hashable, Codable, Equatable {
    var autoDownload: PerFeedOverride
    var keepUpdated: PerFeedOverride
    var notifyOnNewEpisodes: PerFeedOverride
    /// New-episode action override (Use global / Inbox / Queue). Download is global-only.
    var newEpisodeAction: PerFeedNewEpisodeAction
    /// Skip intro seconds override; `nil` = Use global. Explicit `0` = Off for this feed.
    var skipIntroSeconds: Int?
    /// Skip outro seconds override; `nil` = Use global. Explicit `0` = Off for this feed.
    var skipOutroSeconds: Int?
    /// Playback speed override; `nil` = Use global. Explicit value from `AppSettings.speedPresets`.
    var playbackSpeed: Float?

    static let `default` = FeedSettings(
        autoDownload: .useGlobal,
        keepUpdated: .useGlobal,
        notifyOnNewEpisodes: .useGlobal,
        newEpisodeAction: .useGlobal,
        skipIntroSeconds: nil,
        skipOutroSeconds: nil,
        playbackSpeed: nil
    )

    init(
        autoDownload: PerFeedOverride = .useGlobal,
        keepUpdated: PerFeedOverride = .useGlobal,
        notifyOnNewEpisodes: PerFeedOverride = .useGlobal,
        newEpisodeAction: PerFeedNewEpisodeAction = .useGlobal,
        skipIntroSeconds: Int? = nil,
        skipOutroSeconds: Int? = nil,
        playbackSpeed: Float? = nil
    ) {
        self.autoDownload = autoDownload
        self.keepUpdated = keepUpdated
        self.notifyOnNewEpisodes = notifyOnNewEpisodes
        self.newEpisodeAction = newEpisodeAction
        self.skipIntroSeconds = Self.normalizedSkipIntroOutro(skipIntroSeconds)
        self.skipOutroSeconds = Self.normalizedSkipIntroOutro(skipOutroSeconds)
        self.playbackSpeed = Self.normalizedSpeed(playbackSpeed)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoDownload = try c.decodeIfPresent(PerFeedOverride.self, forKey: .autoDownload) ?? .useGlobal
        keepUpdated = try c.decodeIfPresent(PerFeedOverride.self, forKey: .keepUpdated) ?? .useGlobal
        notifyOnNewEpisodes = try c.decodeIfPresent(PerFeedOverride.self, forKey: .notifyOnNewEpisodes) ?? .useGlobal
        newEpisodeAction = try c.decodeIfPresent(PerFeedNewEpisodeAction.self, forKey: .newEpisodeAction) ?? .useGlobal
        skipIntroSeconds = Self.normalizedSkipIntroOutro(
            try c.decodeIfPresent(Int.self, forKey: .skipIntroSeconds)
        )
        skipOutroSeconds = Self.normalizedSkipIntroOutro(
            try c.decodeIfPresent(Int.self, forKey: .skipOutroSeconds)
        )
        playbackSpeed = Self.normalizedSpeed(
            try c.decodeIfPresent(Float.self, forKey: .playbackSpeed)
        )
    }

    /// Whether auto-download may enqueue for this feed (override beats global).
    func allowsAutoDownload(globalEnabled: Bool) -> Bool {
        switch autoDownload {
        case .useGlobal: return globalEnabled
        case .always: return true
        case .never: return false
        }
    }

    /// Whether this feed participates in `refreshAllFeeds` (Never excludes; manual single-feed refresh still works).
    var participatesInBulkRefresh: Bool {
        switch keepUpdated {
        case .useGlobal, .always: return true
        case .never: return false
        }
    }

    /// Whether new-episode local notifications may fire for this feed (override beats global).
    func allowsNotify(globalEnabled: Bool) -> Bool {
        switch notifyOnNewEpisodes {
        case .useGlobal: return globalEnabled
        case .always: return true
        case .never: return false
        }
    }

    /// Skip intro for this feed: override if set, else global.
    func resolvedSkipIntroSeconds(global: Int) -> Int {
        skipIntroSeconds ?? global
    }

    /// Skip outro for this feed: override if set, else global.
    func resolvedSkipOutroSeconds(global: Int) -> Int {
        skipOutroSeconds ?? global
    }

    /// Playback speed for this feed: override if set, else global default.
    func resolvedPlaybackSpeed(global: Float) -> Float {
        playbackSpeed ?? global
    }

    var isDefault: Bool {
        self == .default
    }

    /// Mirrors `AppSettings.skipIntroOutroPresets` (kept local so Codable stays nonisolated).
    private static let skipIntroOutroPresets: Set<Int> = [0, 5, 10, 15, 30, 60]
    /// Mirrors `AppSettings.speedPresets`.
    private static let speedPresets: Set<Float> = [0.8, 1.0, 1.2, 1.5, 2.0]

    private static func normalizedSkipIntroOutro(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return skipIntroOutroPresets.contains(value) ? value : nil
    }

    private static func normalizedSpeed(_ value: Float?) -> Float? {
        guard let value else { return nil }
        return speedPresets.contains(value) ? value : nil
    }

    private enum CodingKeys: String, CodingKey {
        case autoDownload, keepUpdated, notifyOnNewEpisodes, newEpisodeAction
        case skipIntroSeconds, skipOutroSeconds, playbackSpeed
    }
}
