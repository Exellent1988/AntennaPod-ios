import Foundation

/// Tri-state override for per-subscription preferences (Android-style Use global / Always / Never).
enum PerFeedOverride: String, CaseIterable, Identifiable, Codable, Hashable {
    case useGlobal
    case always
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .useGlobal: return String(localized: "Use global")
        case .always: return String(localized: "Always")
        case .never: return String(localized: "Never")
        }
    }

    /// Labels for per-feed **Notify on new episodes** (Use global / On / Off).
    /// Same storage cases as `label`; On maps to `.always`, Off to `.never`.
    var notifyLabel: String {
        switch self {
        case .useGlobal: return String(localized: "Use global")
        case .always: return String(localized: "On")
        case .never: return String(localized: "Off")
        }
    }
}

/// Per-subscription overrides (keyed by `PodcastFeed.id` in a side map), including optional episode list sort.
struct FeedSettings: Hashable, Codable, Equatable {
    var autoDownload: PerFeedOverride
    var keepUpdated: PerFeedOverride
    var notifyOnNewEpisodes: PerFeedOverride
    /// Auto-delete after playing override (Use global / Always / Never). Favorites still skipped.
    var autoDeleteAfterPlaying: PerFeedOverride
    /// New-episode action override (Use global / Inbox / Queue). Download is global-only.
    var newEpisodeAction: PerFeedNewEpisodeAction
    /// Skip intro seconds override; `nil` = Use global. Explicit `0` = Off for this feed.
    var skipIntroSeconds: Int?
    /// Skip outro seconds override; `nil` = Use global. Explicit `0` = Off for this feed.
    var skipOutroSeconds: Int?
    /// Playback speed override; `nil` = Use global. Presets or Custom… (0.50–3.00× @ 0.05).
    /// Applied on fresh episode start and when this value changes while an episode from the
    /// feed is playing. Player session rate (`setRate`) does not write this field.
    var playbackSpeed: Float?
    /// Feed detail episode list sort override; `nil` = Use global (`AppSettings.feedEpisodeSort`).
    /// Newest / Oldest by pubDate; Shortest / Longest by known duration (unknown last).
    /// Capsule itunes:type is display-only; a separate one-shot may set this to `.oldestFirst` when type is serial and this is still nil (never override a user-chosen value; never touch global).
    var episodeSort: FeedEpisodeSort?
    /// Optional local display nickname for this subscription (Android-style custom title).
    /// `nil` = use feed RSS/`PodcastFeed.title`. Trimmed; empty clears to nil; capped at `customTitleMaxLength`.
    /// Local only in `feed-settings.json` — does **not** rename the on-disk feed object or RSS title.
    /// Survives feed refresh; cleared with other FeedSettings on unsubscribe.
    var customTitle: String?

    /// Optional local-only free-text private note for this subscription (not from RSS; not synced).
    /// `nil` = none. Trimmed; empty clears to nil; capped at `privateNoteMaxLength`.
    /// Stored in `feed-settings.json` only — not OPML / gpodder / HTML export (iOS JSON backup snapshots FeedSettings as-is).
    /// Survives feed refresh; cleared with other FeedSettings on unsubscribe.
    var privateNote: String?

    /// Local **Keep at top** preference for the Subscriptions list (AntennaPod-like pin).
    /// Default `false`. When true, this feed sorts above unpinned feeds after filters, for every
    /// `subscriptionsSort` — not a separate Picker sort mode; not synced (gpodder/OPML).
    /// Stored in `feed-settings.json`; survives refresh; cleared with other FeedSettings on unsubscribe.
    /// iOS JSON backup already includes FeedSettings — no side map.
    var isPinned: Bool

    /// Max stored length for `customTitle` (trim first; empty → nil).
    static let customTitleMaxLength = 100

    /// Max stored length for `privateNote` (trim first; empty → nil). ~1k grapheme chars.
    static let privateNoteMaxLength = 1000

    static let `default` = FeedSettings(
        autoDownload: .useGlobal,
        keepUpdated: .useGlobal,
        notifyOnNewEpisodes: .useGlobal,
        autoDeleteAfterPlaying: .useGlobal,
        newEpisodeAction: .useGlobal,
        skipIntroSeconds: nil,
        skipOutroSeconds: nil,
        playbackSpeed: nil,
        episodeSort: nil,
        customTitle: nil,
        privateNote: nil,
        isPinned: false
    )

    init(
        autoDownload: PerFeedOverride = .useGlobal,
        keepUpdated: PerFeedOverride = .useGlobal,
        notifyOnNewEpisodes: PerFeedOverride = .useGlobal,
        autoDeleteAfterPlaying: PerFeedOverride = .useGlobal,
        newEpisodeAction: PerFeedNewEpisodeAction = .useGlobal,
        skipIntroSeconds: Int? = nil,
        skipOutroSeconds: Int? = nil,
        playbackSpeed: Float? = nil,
        episodeSort: FeedEpisodeSort? = nil,
        customTitle: String? = nil,
        privateNote: String? = nil,
        isPinned: Bool = false
    ) {
        self.autoDownload = autoDownload
        self.keepUpdated = keepUpdated
        self.notifyOnNewEpisodes = notifyOnNewEpisodes
        self.autoDeleteAfterPlaying = autoDeleteAfterPlaying
        self.newEpisodeAction = newEpisodeAction
        self.skipIntroSeconds = Self.normalizedSkipIntroOutro(skipIntroSeconds)
        self.skipOutroSeconds = Self.normalizedSkipIntroOutro(skipOutroSeconds)
        self.playbackSpeed = Self.normalizedSpeed(playbackSpeed)
        self.episodeSort = episodeSort
        self.customTitle = Self.normalizedCustomTitle(customTitle)
        self.privateNote = Self.normalizedPrivateNote(privateNote)
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoDownload = try c.decodeIfPresent(PerFeedOverride.self, forKey: .autoDownload) ?? .useGlobal
        keepUpdated = try c.decodeIfPresent(PerFeedOverride.self, forKey: .keepUpdated) ?? .useGlobal
        notifyOnNewEpisodes = try c.decodeIfPresent(PerFeedOverride.self, forKey: .notifyOnNewEpisodes) ?? .useGlobal
        autoDeleteAfterPlaying = try c.decodeIfPresent(PerFeedOverride.self, forKey: .autoDeleteAfterPlaying) ?? .useGlobal
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
        episodeSort = try c.decodeIfPresent(FeedEpisodeSort.self, forKey: .episodeSort)
        customTitle = Self.normalizedCustomTitle(
            try c.decodeIfPresent(String.self, forKey: .customTitle)
        )
        privateNote = Self.normalizedPrivateNote(
            try c.decodeIfPresent(String.self, forKey: .privateNote)
        )
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
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

    /// Whether new-episode local notifications may fire for this feed.
    /// **Global is master:** when Settings → Notify on new episodes is off, no feed notifies
    /// (per-feed On / Always is ignored). Per-feed Off / Never silences that podcast when global is on.
    /// Storage stays `PerFeedOverride` (Use global ≈ nil, On/Always ≈ true, Off/Never ≈ false).
    func allowsNotify(globalEnabled: Bool) -> Bool {
        guard globalEnabled else { return false }
        switch notifyOnNewEpisodes {
        case .useGlobal, .always: return true
        case .never: return false
        }
    }

    /// Whether auto-delete after playing may remove this feed's offline file (override beats global).
    /// Favorites / active-player deferral are enforced separately in PodcastStore.
    func allowsAutoDeleteAfterPlaying(globalEnabled: Bool) -> Bool {
        switch autoDeleteAfterPlaying {
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

    /// Feed detail episode sort: override if set, else global `AppSettings.feedEpisodeSort`.
    func resolvedEpisodeSort(global: FeedEpisodeSort) -> FeedEpisodeSort {
        episodeSort ?? global
    }

    var isDefault: Bool {
        self == .default
    }

    /// Mirrors `AppSettings.skipIntroOutroPresets` (kept local so Codable stays nonisolated).
    private static let skipIntroOutroPresets: Set<Int> = [0, 5, 10, 15, 30, 60]
    /// Mirrors `AppSettings.speedPresets`.
    private static let speedPresets: Set<Float> = [0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0]
    /// Mirrors `PlaybackService.customPlaybackSpeedRange` / step (local so Codable stays nonisolated).
    private static let customSpeedRange: ClosedRange<Float> = 0.5...3.0
    private static let customSpeedStep: Float = 0.05

    private static func normalizedSkipIntroOutro(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return skipIntroOutroPresets.contains(value) ? value : nil
    }

    private static func normalizedSpeed(_ value: Float?) -> Float? {
        guard let value else { return nil }
        if speedPresets.contains(value) {
            return value
        }
        guard customSpeedRange.contains(value) else { return nil }
        let lo = customSpeedRange.lowerBound
        let hi = customSpeedRange.upperBound
        let clamped = min(max(value, lo), hi)
        let stepped = (clamped / customSpeedStep).rounded() * customSpeedStep
        return min(max(stepped, lo), hi)
    }

    private enum CodingKeys: String, CodingKey {
        case autoDownload, keepUpdated, notifyOnNewEpisodes, autoDeleteAfterPlaying, newEpisodeAction
        case skipIntroSeconds, skipOutroSeconds, playbackSpeed, episodeSort, customTitle, privateNote, isPinned
    }

    /// Trim, empty → nil, cap at `customTitleMaxLength` (grapheme-aware via String count).
    static func normalizedCustomTitle(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= customTitleMaxLength {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: customTitleMaxLength)
        let capped = String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }

    /// Trim, empty → nil, cap at `privateNoteMaxLength` (grapheme-aware via String count).
    static func normalizedPrivateNote(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= privateNoteMaxLength {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: privateNoteMaxLength)
        let capped = String(trimmed[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }
}
