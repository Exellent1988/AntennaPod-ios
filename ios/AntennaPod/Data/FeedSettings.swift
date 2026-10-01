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

    static let `default` = FeedSettings(
        autoDownload: .useGlobal,
        keepUpdated: .useGlobal,
        notifyOnNewEpisodes: .useGlobal,
        newEpisodeAction: .useGlobal
    )

    init(
        autoDownload: PerFeedOverride = .useGlobal,
        keepUpdated: PerFeedOverride = .useGlobal,
        notifyOnNewEpisodes: PerFeedOverride = .useGlobal,
        newEpisodeAction: PerFeedNewEpisodeAction = .useGlobal
    ) {
        self.autoDownload = autoDownload
        self.keepUpdated = keepUpdated
        self.notifyOnNewEpisodes = notifyOnNewEpisodes
        self.newEpisodeAction = newEpisodeAction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoDownload = try c.decodeIfPresent(PerFeedOverride.self, forKey: .autoDownload) ?? .useGlobal
        keepUpdated = try c.decodeIfPresent(PerFeedOverride.self, forKey: .keepUpdated) ?? .useGlobal
        notifyOnNewEpisodes = try c.decodeIfPresent(PerFeedOverride.self, forKey: .notifyOnNewEpisodes) ?? .useGlobal
        newEpisodeAction = try c.decodeIfPresent(PerFeedNewEpisodeAction.self, forKey: .newEpisodeAction) ?? .useGlobal
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

    var isDefault: Bool {
        self == .default
    }

    private enum CodingKeys: String, CodingKey {
        case autoDownload, keepUpdated, notifyOnNewEpisodes, newEpisodeAction
    }
}
