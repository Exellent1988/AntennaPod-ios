import Foundation
import SwiftUI

/// Appearance preference persisted for `preferredColorScheme`.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    /// `nil` follows the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Optional accent tint — system named SwiftUI colors only (no custom assets / Android themes).
enum AppAccentColor: String, CaseIterable, Identifiable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case indigo
    case brown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .blue: return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .pink: return String(localized: "Pink")
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .mint: return String(localized: "Mint")
        case .teal: return String(localized: "Teal")
        case .cyan: return String(localized: "Cyan")
        case .indigo: return String(localized: "Indigo")
        case .brown: return String(localized: "Brown")
        }
    }

    /// `nil` keeps the default app / iOS accent (no override).
    var tintColor: Color? {
        switch self {
        case .system: return nil
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .indigo: return .indigo
        case .brown: return .brown
        }
    }
}

/// Max size of Documents/downloads (P0 Speicherverwaltung).
/// Byte budget (MB/GB). Episode *count* cache is `DownloadEpisodeCacheLimit` (Android-like).
enum DownloadStorageLimit: Equatable, Hashable, Identifiable {
    case unlimited
    case gigabytes(Int)
    case customMegabytes(Int)

    var id: String {
        switch self {
        case .unlimited: return "unlimited"
        case .gigabytes(let gb): return "gb-\(gb)"
        case .customMegabytes(let mb): return "custom-\(mb)"
        }
    }

    /// `nil` means no eviction by size.
    var byteLimit: Int64? {
        switch self {
        case .unlimited:
            return nil
        case .gigabytes(let gb):
            return Int64(gb) * 1_024 * 1_024 * 1_024
        case .customMegabytes(let mb):
            return Int64(max(1, mb)) * 1_024 * 1_024
        }
    }

    var label: String {
        switch self {
        case .unlimited:
            return "Unlimited"
        case .gigabytes(let gb):
            return "\(gb) GB"
        case .customMegabytes(let mb):
            return "\(mb) MB"
        }
    }

    /// Presets shown in the Settings picker (custom is selected separately when MB ≠ presets).
    static let pickerPresets: [DownloadStorageLimit] = [
        .unlimited,
        .gigabytes(1),
        .gigabytes(5),
        .gigabytes(10),
        .customMegabytes(500)
    ]
}

/// How often subscribed feeds are auto-refreshed (global; all feeds).
enum FeedRefreshInterval: String, CaseIterable, Identifiable {
    case manual
    case oneHour
    case fourHours
    case twelveHours
    case twentyFourHours

    var id: String { rawValue }

    /// `nil` means never auto-refresh (manual / pull-to-refresh only).
    var timeInterval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .oneHour: return 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .manual: return "Manual only"
        case .oneHour: return "Every 1 hour"
        case .fourHours: return "Every 4 hours"
        case .twelveHours: return "Every 12 hours"
        case .twentyFourHours: return "Every 24 hours"
        }
    }
}


/// Cap: how many **newly appeared** unplayed episodes per feed auto-download may enqueue after refresh.
enum AutoDownloadEpisodesPerFeed: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case five = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .one: return String(localized: "1 episode")
        case .two: return String(localized: "2 episodes")
        case .three: return String(localized: "3 episodes")
        case .five: return String(localized: "5 episodes")
        }
    }
}


/// Cap: how many episode downloads may run as active URLSession tasks at once (1–5).
enum MaxParallelDownloads: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .one: return String(localized: "1 at a time")
        case .two: return String(localized: "2 parallel")
        case .three: return String(localized: "3 parallel")
        case .four: return String(localized: "4 parallel")
        case .five: return String(localized: "5 parallel")
        }
    }
}


/// Cap: how many **completed** offline downloads to keep (episode count cache).
/// `0` = Unlimited. When over the cap, `DownloadService` evicts eligible files
/// (played non-favorite non-queued first; favorites and queued are never auto-deleted by this cap).
enum DownloadEpisodeCacheLimit: Int, CaseIterable, Identifiable {
    case twentyFive = 25
    case fifty = 50
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case unlimited = 0

    var id: Int { rawValue }

    /// `nil` means no eviction by episode count.
    var episodeLimit: Int? {
        self == .unlimited ? nil : rawValue
    }

    var label: String {
        switch self {
        case .twentyFive: return String(localized: "25 episodes")
        case .fifty: return String(localized: "50 episodes")
        case .oneHundred: return String(localized: "100 episodes")
        case .twoHundred: return String(localized: "200 episodes")
        case .fiveHundred: return String(localized: "500 episodes")
        case .unlimited: return String(localized: "Unlimited")
        }
    }
}


/// Preferred media source when starting playback (P0 Prefer stream vs download).
enum PlaybackSourcePreference: String, CaseIterable, Identifiable {
    /// Use local file when present; otherwise stream.
    case preferDownload
    /// Always use the network media URL, even if a download exists.
    case preferStream
    /// Default: local file if present, else stream (same resolution as prefer download).
    case automatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preferDownload: return "Prefer download"
        case .preferStream: return "Prefer stream"
        case .automatic: return "Automatic"
        }
    }

    var helpText: String {
        switch self {
        case .preferDownload:
            return String(localized: "Play the offline file when available; otherwise stream from the network.")
        case .preferStream:
            return String(localized: "Always stream from the network URL, even if the episode is downloaded.")
        case .automatic:
            return String(localized: "Use the local file when it exists; otherwise stream. Default.")
        }
    }
}


/// Charts country for iTunes top podcasts. Empty / `auto` → device locale (fallback `de`).
enum ChartsCountryPreference: Equatable, Hashable, Identifiable {
    case automatic
    case code(String)

    var id: String {
        switch self {
        case .automatic: return "auto"
        case .code(let c): return c.lowercased()
        }
    }

    var storageValue: String {
        switch self {
        case .automatic: return "auto"
        case .code(let c): return c.lowercased()
        }
    }

    static func fromStorage(_ raw: String?) -> ChartsCountryPreference {
        let v = (raw ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if v.isEmpty || v == "auto" { return .automatic }
        let code = ItunesTopListService.normalizedCountryCode(v)
        return code.isEmpty ? .automatic : .code(code)
    }

    /// Curated picker list (ISO alpha-2); includes common AntennaPod locales.
    static let pickerCodes: [String] = [
        "de", "at", "ch", "us", "gb", "ie", "fr", "nl", "be", "es", "it",
        "pt", "pl", "se", "no", "dk", "fi", "cz", "au", "ca", "jp", "br", "mx", "in"
    ]
}



/// How the Subscriptions tab orders the feed list (client-side only; no drag-reorder).
enum SubscriptionsSort: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case alphabetical
    case byAuthor
    case byLanguage
    /// Descending unplayed count (`!isPlayed && !isArchived` — same as badges / Inbox).
    case mostUnplayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyUpdated: return String(localized: "Recently updated")
        case .alphabetical: return String(localized: "Alphabetical A–Z")
        case .byAuthor: return String(localized: "Author A–Z")
        case .byLanguage: return String(localized: "Language A–Z")
        case .mostUnplayed: return String(localized: "Most unplayed")
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyUpdated: return "clock.arrow.circlepath"
        case .alphabetical: return "textformat.abc"
        case .byAuthor: return "person"
        case .byLanguage: return "globe"
        case .mostUnplayed: return "number"
        }
    }
}



/// How Feed detail orders episodes in one podcast (client-side; All Episodes unchanged; Inbox has its own `inboxSort`).
/// Global default for feeds with `FeedSettings.episodeSort == nil` (Use global). Per-feed override lives in `feed-settings.json`.
/// Newest / Oldest by `pubDateEpochMs` only — no duration/title modes. itunes:type must not auto-change this.
enum FeedEpisodeSort: String, CaseIterable, Identifiable, Codable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}


/// Filter chips on Feed detail episode list. Uses PodcastStore.isPlayed (+ archive for Unplayed).
enum FeedEpisodeFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case played

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .unplayed: return String(localized: "Unplayed")
        case .played: return String(localized: "Played")
        }
    }
}

/// How the Inbox tab orders episodes (client-side; Home New preview stays newest-first).
enum InboxSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}

/// Podcast chip selection on the Inbox list (feeds that currently have Inbox
/// episodes only — never invent podcasts). Empty storage = All; otherwise feed UUID string.
enum InboxPodcastFilter: Hashable, Identifiable {
    case all
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .feed(let id): return "feed:\(id.uuidString)"
        }
    }

    /// Persistable raw value: empty = All; otherwise the feed UUID string.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .feed(let id): return id.uuidString
        }
    }

    static func fromStorage(_ raw: String?) -> InboxPodcastFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = UUID(uuidString: trimmed) else { return .all }
        return .feed(id)
    }
}

/// How the Downloads tab orders offline episodes (client-side; prefer download completion time).
enum DownloadsSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}

/// How the History list orders episodes (client-side; by last-played / history timestamp).
enum HistorySort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}

/// Podcast chip selection on the History list (feeds that currently have history
/// episodes only — never invent podcasts). Empty storage = All; otherwise feed UUID string.
enum HistoryPodcastFilter: Hashable, Identifiable {
    case all
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .feed(let id): return "feed:\(id.uuidString)"
        }
    }

    /// Persistable raw value: empty = All; otherwise the feed UUID string.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .feed(let id): return id.uuidString
        }
    }

    static func fromStorage(_ raw: String?) -> HistoryPodcastFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = UUID(uuidString: trimmed) else { return .all }
        return .feed(id)
    }
}

/// Cap on History-listed episodes (played / in-progress in `playback.json`).
/// **No separate history.json** — History is derived from `playbackStates`. Trimming drops the oldest
/// history-eligible entries (same as Remove from history): progress + `isPlayed` + `lastPlayedAt` gone.
/// Favorites, archive, downloads, and queue are untouched. Statistics / Echo / Continue listening may
/// lose those episodes’ estimates. **Unlimited** = no automatic trim (default).
enum HistorySizeLimit: Int, CaseIterable, Identifiable {
    case fifty = 50
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case unlimited = 0

    var id: Int { rawValue }

    /// `nil` means no automatic trim.
    var entryLimit: Int? {
        self == .unlimited ? nil : rawValue
    }

    var label: String {
        switch self {
        case .fifty: return String(localized: "50 episodes")
        case .oneHundred: return String(localized: "100 episodes")
        case .twoHundred: return String(localized: "200 episodes")
        case .fiveHundred: return String(localized: "500 episodes")
        case .unlimited: return String(localized: "Unlimited")
        }
    }
}

/// How the Favorites list orders episodes (client-side; by favorited-at timestamp).
enum FavoritesSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}



/// Podcast chip selection on the Favorites list (feeds that currently have favorite
/// episodes only — never invent podcasts). Empty storage = All; otherwise feed UUID string.
enum FavoritesPodcastFilter: Hashable, Identifiable {
    case all
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .feed(let id): return "feed:\(id.uuidString)"
        }
    }

    /// Persistable raw value: empty = All; otherwise the feed UUID string.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .feed(let id): return id.uuidString
        }
    }

    static func fromStorage(_ raw: String?) -> FavoritesPodcastFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = UUID(uuidString: trimmed) else { return .all }
        return .feed(id)
    }
}

/// How the Archived list orders episodes (client-side; by archived-at timestamp).
enum ArchivedSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}

/// Filter chips on Downloads tab. Uses PodcastStore.isPlayed on downloaded episodes.
enum DownloadsFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case played

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .unplayed: return String(localized: "Unplayed")
        case .played: return String(localized: "Played")
        }
    }
}

/// Podcast chip selection on the Downloads list (feeds that currently have downloaded
/// episodes only — never invent podcasts). Empty storage = All; otherwise feed UUID string.
enum DownloadsPodcastFilter: Hashable, Identifiable {
    case all
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .feed(let id): return "feed:\(id.uuidString)"
        }
    }

    /// Persistable raw value: empty = All; otherwise the feed UUID string.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .feed(let id): return id.uuidString
        }
    }

    static func fromStorage(_ raw: String?) -> DownloadsPodcastFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = UUID(uuidString: trimmed) else { return .all }
        return .feed(id)
    }
}

/// Filter chips on Queue tab. Uses PodcastStore.isPlayed on queued episodes
/// (archive ignored — same honesty as Downloads; queue can still hold archived items).
enum QueueFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case played

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .unplayed: return String(localized: "Unplayed")
        case .played: return String(localized: "Played")
        }
    }
}

/// Podcast chip selection on the Queue list (feeds that currently have queued
/// episodes only — never invent podcasts). Empty storage = All; otherwise feed UUID string.
enum QueuePodcastFilter: Hashable, Identifiable {
    case all
    case feed(UUID)

    var id: String {
        switch self {
        case .all: return "__all__"
        case .feed(let id): return "feed:\(id.uuidString)"
        }
    }

    /// Persistable raw value: empty = All; otherwise the feed UUID string.
    var storageValue: String {
        switch self {
        case .all: return ""
        case .feed(let id): return id.uuidString
        }
    }

    static func fromStorage(_ raw: String?) -> QueuePodcastFilter {
        guard let raw else { return .all }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = UUID(uuidString: trimmed) else { return .all }
        return .feed(id)
    }
}

/// Filter chips on Library → Episodes (All Episodes). Applied after the newest-500 soft cap.
enum AllEpisodesFilter: String, CaseIterable, Identifiable {
    case all
    case unplayed
    case downloaded
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return String(localized: "All")
        case .unplayed: return String(localized: "Unplayed")
        case .downloaded: return String(localized: "Downloaded")
        case .favorites: return String(localized: "Favorites")
        }
    }
}

/// How Library → Episodes (All Episodes) orders the soft-capped list (client-side; by pubDate).
enum AllEpisodesSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newestFirst: return String(localized: "Newest first")
        case .oldestFirst: return String(localized: "Oldest first")
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: return "arrow.down"
        case .oldestFirst: return "arrow.up"
        }
    }
}

/// Configurable Home tab sections (order + show/hide). Mirrors Android HomePreferences lite.
enum HomeSectionId: String, CaseIterable, Identifiable, Codable, Hashable {
    case continueListening
    case inbox
    case queue
    case discover
    case recentlyUpdated
    case favorites

    var id: String { rawValue }

    var label: String {
        switch self {
        case .continueListening: return String(localized: "Continue listening")
        case .inbox: return String(localized: "New / Inbox")
        case .queue: return String(localized: "Queue")
        case .discover: return String(localized: "Discover")
        case .recentlyUpdated: return String(localized: "Recently updated")
        case .favorites: return String(localized: "Favorites")
        }
    }

    var systemImage: String {
        switch self {
        case .continueListening: return "play.circle"
        case .inbox: return "tray.fill"
        case .queue: return "list.bullet"
        case .discover: return "chart.bar"
        case .recentlyUpdated: return "dot.radiowaves.left.and.right"
        case .favorites: return "star"
        }
    }

    /// Default order matches the previous fixed Home layout (Discover first).
    static let defaultOrder: [HomeSectionId] = [
        .discover, .continueListening, .inbox, .queue, .recentlyUpdated, .favorites
    ]

    /// Favorites starts hidden so enabling it is opt-in (optional Home preview).
    static let defaultHidden: Set<HomeSectionId> = [.favorites]
}


/// Time range for Statistics / Echo aggregations (device calendar; default All time).
/// Filters by `lastPlayedAtEpochMs` else `updatedAtEpochMs` — coarse episode-level stamps, not per-session listen windows.
enum StatisticsTimeRange: String, CaseIterable, Identifiable {
    case thisWeek
    case thisMonth
    case thisYear
    case allTime

    var id: String { rawValue }

    /// Short label for segmented control / chips.
    var label: String {
        switch self {
        case .thisWeek: return String(localized: "This week")
        case .thisMonth: return String(localized: "This month")
        case .thisYear: return String(localized: "This year")
        case .allTime: return String(localized: "All time")
        }
    }

    /// Compact label when space is tight (segmented).
    var shortLabel: String {
        switch self {
        case .thisWeek: return String(localized: "Week")
        case .thisMonth: return String(localized: "Month")
        case .thisYear: return String(localized: "Year")
        case .allTime: return String(localized: "All")
        }
    }

    var systemImage: String {
        switch self {
        case .thisWeek: return "calendar"
        case .thisMonth: return "calendar"
        case .thisYear: return "calendar"
        case .allTime: return "infinity"
        }
    }

    /// Inclusive start / exclusive end epoch ms for the selected calendar unit containing `now`.
    /// `nil` means no lower/upper bound (All time).
    func epochRangeMs(calendar: Calendar = .current, now: Date = Date()) -> (startMs: Int64, endMs: Int64)? {
        let component: Calendar.Component
        switch self {
        case .allTime:
            return nil
        case .thisWeek:
            component = .weekOfYear
        case .thisMonth:
            component = .month
        case .thisYear:
            component = .year
        }
        guard let interval = calendar.dateInterval(of: component, for: now) else {
            return nil
        }
        let startMs = Int64(interval.start.timeIntervalSince1970 * 1000)
        let endMs = Int64(interval.end.timeIntervalSince1970 * 1000)
        return (startMs, endMs)
    }

    /// Whether an episode-level timestamp falls in this range.
    func contains(epochMs: Int64, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        guard let bounds = epochRangeMs(calendar: calendar, now: now) else {
            return true
        }
        return epochMs >= bounds.startMs && epochMs < bounds.endMs
    }
}


/// User preferences for P0 Settings (theme, accent tint, default playback speed, download storage limit, max downloaded episodes (episode cache), max parallel downloads, refresh, new-episode action, auto-download, network/Wi‑Fi policy, playback source, auto-delete, skip intervals (presets + Custom… 5–60s), smart mark (presets + Custom… 1–600s), Custom… sleep last minutes, skip intro/outro, volume adaptation, skip silence preference, Stereo to mono, Preserve pitch, new-episode / download-error / sync-error notifications, App Store rating prompt, play video as audio only, Keep screen on, Continuous playback, Show remaining time, rewind after pause, smart mark as played, Home section order/visibility, subscriptions list sort (incl. author / language A–Z), subscriptions category filter, subscriptions language filter, feed episode list sort (global default + per-feed `FeedSettings.episodeSort`), Inbox sort, Downloads sort, History sort, History podcast filter, History size limit, Favorites sort, Favorites podcast filter, Archived sort, All Episodes filter chips, All Episodes sort, Downloads filter chips, Downloads podcast filter, Feed detail episode filter chips, Queue filter chips, queue lock, Statistics/Echo time range, Statistics reset baseline).
@MainActor
final class AppSettings: ObservableObject {
    static let speedPresets: [Float] = [0.8, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0]
    /// Common AntennaPod-style skip presets (Settings pickers + player buttons).
    static let skipIntervalPresets: [Int] = [5, 10, 15, 20, 30, 60]
    /// Skip intro / outro presets (0 = off). Matches common AntennaPod values.
    static let skipIntroOutroPresets: [Int] = [0, 5, 10, 15, 30, 60]
    /// Smart mark as played presets (0 = off). AntennaPod `prefSmartMarkAsPlayedSecs` values + Custom… 1–600.
    static let smartMarkAsPlayedPresets: [Int] = [0, 15, 30, 60, 120, 300, 600]
    /// Rewind-after-pause presets (0 = off). Simpler than Android's graduated elapsed buckets; default 2s.
    static let rewindAfterPausePresets: [Int] = [0, 1, 2, 3, 5, 10]
    /// Android `prefRewindSecs` default.
    static let defaultRewindSeconds: Int = 10
    /// Android `prefFastForwardSecs` default.
    static let defaultFastForwardSeconds: Int = 30
    /// Global skip intro / outro default (off).
    static let defaultSkipIntroOutroSeconds: Int = 0
    /// Android `prefSmartMarkAsPlayedSecs` default.
    static let defaultSmartMarkAsPlayedSeconds: Int = 30
    /// Fixed rewind after a real pause (honest beta; not Android's elapsed-tier util). Default 2.
    static let defaultRewindAfterPauseSeconds: Int = 2
    /// Last Custom… sleep timer minutes (Android SleepTimerPreferences LastValue default 15).
    static let defaultLastCustomSleepTimerMinutes: Int = 15
    /// Minimum pause duration before rewind-after-pause applies (avoids accidental pause/play).
    static let rewindAfterPauseMinimumPauseSeconds: Double = 1
    static let customStorageMBRange = 50...100_000

    /// SF Symbol for skip buttons (`gobackward.10`, `goforward.30`, …). Falls back to unnumbered glyph when no preset icon exists (e.g. 20s).
    static func skipSystemImage(forward: Bool, seconds: Int) -> String {
        let base = forward ? "goforward" : "gobackward"
        switch seconds {
        case 5, 10, 15, 30, 45, 60, 75, 90:
            return "\(base).\(seconds)"
        default:
            return base
        }
    }


    /// Localized label for skip interval pickers / Custom… sheet (e.g. "25 seconds").
    static func skipIntervalLabel(_ seconds: Int) -> String {
        String(localized: "\(seconds) seconds")
    }


    private enum Keys {
        static let theme = "settings.theme"
        static let accentColor = "settings.accentColor"
        static let defaultPlaybackSpeed = "settings.defaultPlaybackSpeed"
        static let storageLimitKind = "settings.storageLimit.kind"
        static let storageLimitValue = "settings.storageLimit.value"
        static let refreshInterval = "settings.refreshInterval"
        static let lastFeedRefreshAt = "settings.lastFeedRefreshAt"
        static let newEpisodeAction = "settings.newEpisodeAction"
        static let autoDownloadEnabled = "settings.autoDownload.enabled"
        static let autoDownloadEpisodesPerFeed = "settings.autoDownload.episodesPerFeed"
        static let maxParallelDownloads = "settings.maxParallelDownloads"
        static let downloadEpisodeCacheLimit = "settings.downloadEpisodeCacheLimit"
        static let autoDownloadWifiOnly = "settings.autoDownload.wifiOnly"
        static let manualDownloadWifiOnly = "settings.manualDownload.wifiOnly"
        static let streamWifiOnly = "settings.stream.wifiOnly"
        static let playbackSourcePreference = "settings.playbackSourcePreference"
        static let autoDeleteAfterPlaying = "settings.autoDelete.afterPlaying"
        static let rewindSeconds = "settings.rewindSeconds"
        static let fastForwardSeconds = "settings.fastForwardSeconds"
        static let skipIntroSeconds = "settings.skipIntroSeconds"
        static let skipOutroSeconds = "settings.skipOutroSeconds"
        static let notifyOnNewEpisodes = "settings.notifyOnNewEpisodes"
        static let notifyOnDownloadErrors = "settings.notifyOnDownloadErrors"
        static let notifyOnSyncErrors = "settings.notifyOnSyncErrors"
        static let notifyOnSleepTimerEnd = "settings.notifyOnSleepTimerEnd"
        static let lastCustomSleepTimerMinutes = "settings.lastCustomSleepTimerMinutes"
        static let chartsCountryCode = "settings.chartsCountryCode"
        static let askForAppStoreRating = "settings.askForAppStoreRating"
        static let playVideoAsAudioOnly = "settings.playVideoAsAudioOnly"
        static let volumeAdaptationEnabled = "settings.volumeAdaptationEnabled"
        static let skipSilenceEnabled = "settings.skipSilenceEnabled"
        static let stereoToMonoEnabled = "settings.stereoToMonoEnabled"
        static let preservePitchEnabled = "settings.preservePitchEnabled"
        static let customUserAgent = "settings.customUserAgent"
        static let keepScreenOnWhilePlaying = "settings.keepScreenOnWhilePlaying"
        static let continuousPlaybackEnabled = "settings.continuousPlaybackEnabled"
        static let resetPositionWhenMarkedPlayed = "settings.resetPositionWhenMarkedPlayed"
        static let showRemainingTime = "settings.showRemainingTime"
        static let rewindAfterPauseSeconds = "settings.rewindAfterPauseSeconds"
        static let smartMarkAsPlayedSeconds = "settings.smartMarkAsPlayedSeconds"
        static let homeSectionOrder = "settings.home.sectionOrder"
        static let homeHiddenSections = "settings.home.hiddenSections"
        static let subscriptionsSort = "settings.subscriptionsSort"
        static let subscriptionsCategoryFilter = "settings.subscriptionsCategoryFilter"
        static let subscriptionsLanguageFilter = "settings.subscriptionsLanguageFilter"
        static let feedEpisodeSort = "settings.feedEpisodeSort"
        static let feedEpisodeFilter = "settings.feedEpisodeFilter"
        static let inboxSort = "settings.inboxSort"
        static let inboxPodcastFilter = "settings.inboxPodcastFilter"
        static let downloadsSort = "settings.downloadsSort"
        static let downloadsFilter = "settings.downloadsFilter"
        static let downloadsPodcastFilter = "settings.downloadsPodcastFilter"
        static let historySort = "settings.historySort"
        static let historyPodcastFilter = "settings.historyPodcastFilter"
        static let historySizeLimit = "settings.historySizeLimit"
        static let favoritesSort = "settings.favoritesSort"
        static let favoritesPodcastFilter = "settings.favoritesPodcastFilter"
        static let archivedSort = "settings.archivedSort"
        static let allEpisodesFilter = "settings.allEpisodesFilter"
        static let allEpisodesSort = "settings.allEpisodesSort"
        static let queueLocked = "settings.queueLocked"
        static let queueFilter = "settings.queueFilter"
        static let queuePodcastFilter = "settings.queuePodcastFilter"
        static let statisticsTimeRange = "settings.statisticsTimeRange"
        /// Epoch ms baseline after Reset statistics; 0 = count all (default).
        static let statisticsResetAtEpochMs = "settings.statisticsResetAtEpochMs"
    }

    private enum Kind: String {
        case unlimited
        case gigabytes
        case customMegabytes
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    /// Optional accent tint (system named colors). Default `.system` = no override.
    @Published var accentColor: AppAccentColor {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: Keys.accentColor)
        }
    }

    @Published var defaultPlaybackSpeed: Float {
        didSet {
            UserDefaults.standard.set(defaultPlaybackSpeed, forKey: Keys.defaultPlaybackSpeed)
        }
    }

    /// Max download folder size. Changing it persists immediately; callers should run eviction.
    @Published var downloadStorageLimit: DownloadStorageLimit {
        didSet {
            persistStorageLimit()
        }
    }

    /// Global auto-refresh cadence for all subscribed feeds (Keep updated).
    @Published var refreshInterval: FeedRefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Keys.refreshInterval)
        }
    }

    /// Wall-clock of the last completed `refreshAllFeeds()` (manual or automatic).
    @Published var lastFeedRefreshAt: Date? {
        didSet {
            if let lastFeedRefreshAt {
                UserDefaults.standard.set(lastFeedRefreshAt.timeIntervalSince1970, forKey: Keys.lastFeedRefreshAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.lastFeedRefreshAt)
            }
        }
    }

    /// Global action for newly discovered episodes after refresh (Inbox only / Queue / Queue+download).
    @Published var newEpisodeAction: NewEpisodeAction {
        didSet {
            UserDefaults.standard.set(newEpisodeAction.rawValue, forKey: Keys.newEpisodeAction)
        }
    }

    /// Global auto-download after feed refresh (newly appeared unplayed IDs only, not backlog).
    @Published var autoDownloadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadEnabled, forKey: Keys.autoDownloadEnabled)
        }
    }

    /// Cap per feed to avoid download storms (1 / 2 / 3 / 5).
    @Published var autoDownloadEpisodesPerFeed: AutoDownloadEpisodesPerFeed {
        didSet {
            UserDefaults.standard.set(autoDownloadEpisodesPerFeed.rawValue, forKey: Keys.autoDownloadEpisodesPerFeed)
        }
    }

    /// Cap concurrent active URLSession download tasks (1–5, default 3). Extra enqueues wait in memory.
    @Published var maxParallelDownloads: MaxParallelDownloads {
        didSet {
            UserDefaults.standard.set(maxParallelDownloads.rawValue, forKey: Keys.maxParallelDownloads)
        }
    }

    /// Max completed offline downloads to keep (25/50/100/200/500 or Unlimited). Default Unlimited.
    @Published var downloadEpisodeCacheLimit: DownloadEpisodeCacheLimit {
        didSet {
            UserDefaults.standard.set(downloadEpisodeCacheLimit.rawValue, forKey: Keys.downloadEpisodeCacheLimit)
        }
    }

    /// When true, auto-download enqueues only on Wi‑Fi / Ethernet (`NWPathMonitor`).
    @Published var autoDownloadWifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(autoDownloadWifiOnly, forKey: Keys.autoDownloadWifiOnly)
        }
    }

    /// When true, manual downloads are refused on cellular (error recorded; default off).
    @Published var manualDownloadWifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(manualDownloadWifiOnly, forKey: Keys.manualDownloadWifiOnly)
        }
    }

    /// When true, `PlaybackService` refuses stream URLs on cellular; local files still play (default off).
    @Published var streamWifiOnly: Bool {
        didSet {
            UserDefaults.standard.set(streamWifiOnly, forKey: Keys.streamWifiOnly)
        }
    }

    /// Prefer local download, always stream, or automatic (local if present).
    @Published var playbackSourcePreference: PlaybackSourcePreference {
        didSet {
            UserDefaults.standard.set(playbackSourcePreference.rawValue, forKey: Keys.playbackSourcePreference)
        }
    }

    /// When true, delete the local download after an episode is marked played (file only; DB row kept).
    @Published var autoDeleteAfterPlaying: Bool {
        didSet {
            UserDefaults.standard.set(autoDeleteAfterPlaying, forKey: Keys.autoDeleteAfterPlaying)
        }
    }

    /// Seconds to jump backward on rewind / skip-back (Android `prefRewindSecs`, default 10).
    @Published var rewindSeconds: Int {
        didSet {
            UserDefaults.standard.set(rewindSeconds, forKey: Keys.rewindSeconds)
        }
    }

    /// Seconds to jump forward on fast-forward / skip-forward (Android `prefFastForwardSecs`, default 30).
    @Published var fastForwardSeconds: Int {
        didSet {
            UserDefaults.standard.set(fastForwardSeconds, forKey: Keys.fastForwardSeconds)
        }
    }

    /// Seconds to skip at the start of an episode on a fresh play (0 = off). Overridable per feed.
    @Published var skipIntroSeconds: Int {
        didSet {
            UserDefaults.standard.set(skipIntroSeconds, forKey: Keys.skipIntroSeconds)
        }
    }

    /// When remaining playback ≤ this many seconds, treat the episode as finished (0 = off). Overridable per feed.
    @Published var skipOutroSeconds: Int {
        didSet {
            UserDefaults.standard.set(skipOutroSeconds, forKey: Keys.skipOutroSeconds)
        }
    }

    /// Notify when feed refresh discovers new episodes (local UserNotifications; no push).
    /// Defaults **off**; actual delivery still requires system permission (Settings stays honest if denied).
    @Published var notifyOnNewEpisodes: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnNewEpisodes, forKey: Keys.notifyOnNewEpisodes)
        }
    }

    /// Notify when an episode download fails (local UserNotifications; no push).
    /// Defaults on; shares the same system permission as new-episode alerts.
    @Published var notifyOnDownloadErrors: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnDownloadErrors, forKey: Keys.notifyOnDownloadErrors)
        }
    }

    /// Notify when gpodder / Nextcloud login or sync fails (local UserNotifications; no push).
    /// Defaults on; shares the same system permission as new-episode / download-error alerts.
    @Published var notifyOnSyncErrors: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnSyncErrors, forKey: Keys.notifyOnSyncErrors)
        }
    }

    /// Notify when the sleep timer ends (local UserNotifications + foreground haptic; no push).
    /// Defaults on; shares the same system permission as new-episode / DL / sync alerts.
    @Published var notifyOnSleepTimerEnd: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnSleepTimerEnd, forKey: Keys.notifyOnSleepTimerEnd)
        }
    }

    /// Last duration chosen in the Custom… sleep timer sheet (1–180). Seeds the next Custom… open.
    /// AntennaPod Android `SleepTimerPreferences` LastValue honesty — presets unchanged; fade unchanged.
    @Published var lastCustomSleepTimerMinutes: Int {
        didSet {
            UserDefaults.standard.set(lastCustomSleepTimerMinutes, forKey: Keys.lastCustomSleepTimerMinutes)
        }
    }

    /// iTunes top-lists country: `"auto"` (device locale → else `de`) or ISO alpha-2 (`de`, `us`, …).
    @Published var chartsCountryCode: String {
        didSet {
            UserDefaults.standard.set(chartsCountryCode, forKey: Keys.chartsCountryCode)
        }
    }


    /// When true, after ~10 successful mark-played events ask iOS once for an App Store rating sheet.
    /// Defaults on; iOS may still suppress the dialog (system limits). Reset via Settings for testing.
    @Published var askForAppStoreRating: Bool {
        didSet {
            UserDefaults.standard.set(askForAppStoreRating, forKey: Keys.askForAppStoreRating)
        }
    }

    /// When true, video episodes hide the full-player video surface and show artwork (audio-style).
    /// Default off; Lockscreen / Now Playing stays audio either way. Media item is unchanged (lite).
    @Published var playVideoAsAudioOnly: Bool {
        didSet {
            UserDefaults.standard.set(playVideoAsAudioOnly, forKey: Keys.playVideoAsAudioOnly)
        }
    }

    /// When true, `PlaybackService` sets `AVAudioSession` mode to `.spokenAudio` (speech-oriented session mode).
    /// Default off. This is an **iOS session mode**, not Android's LoudnessEnhancer gain curve.
    @Published var volumeAdaptationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(volumeAdaptationEnabled, forKey: Keys.volumeAdaptationEnabled)
        }
    }

    /// Preference for skip-silence (AntennaPod Android / ExoPlayer). Default off.
    /// **Not applied** on stock `AVPlayer` — needs a custom `AVAudioEngine` graph (would break shared video / Now Playing). Toggle is honest UI + future hook only.
    @Published var skipSilenceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(skipSilenceEnabled, forKey: Keys.skipSilenceEnabled)
        }
    }

    /// When true, `PlaybackService` best-effort requests mono output via `AVAudioSession.setPreferredOutputNumberOfChannels(1)`.
    /// Default off. Route-dependent (system may ignore); reapplied on play, Settings change, and route change.
    /// Keeps stock `AVPlayer` (video / PiP / Now Playing). **Not** `AVMutableAudioMix` remix (volume only) /
    /// **not** `MTAudioProcessingTap` (file-only) / **not** `AVAudioEngine` / **not** Android ExoPlayer channel remix.
    @Published var stereoToMonoEnabled: Bool {
        didSet {
            UserDefaults.standard.set(stereoToMonoEnabled, forKey: Keys.stereoToMonoEnabled)
        }
    }

    /// When true, `PlaybackService` sets `AVPlayerItem.audioTimePitchAlgorithm` to `.timeDomain` (pitch stays natural when speed ≠ 1×).
    /// When false → `.varispeed` (pitch scales with rate — chipmunk / slow voice). Default **on** (speech-friendly; matches common iOS AVPlayer pitch correction).
    /// Stock `AVPlayer` only — not Android ExoPlayer / Sonic. Not Skip Silence.
    @Published var preservePitchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(preservePitchEnabled, forKey: Keys.preservePitchEnabled)
        }
    }

    /// Optional custom HTTP `User-Agent` for feed refresh + media downloads (and other URLSession clients).
    /// Empty (after sanitize) → app default `AntennaPod-iOS/0.1`. Newlines/controls stripped (header safety).
    /// **Not** applied to stock `AVPlayer` streaming (system UA). Not a proxy / not certificate pinning.
    /// Persisted + iOS JSON backup. Default empty.
    @Published var customUserAgent: String {
        didSet {
            let sanitized = AppUserAgent.sanitize(customUserAgent)
            if sanitized != customUserAgent {
                customUserAgent = sanitized
                return
            }
            UserDefaults.standard.set(customUserAgent, forKey: Keys.customUserAgent)
        }
    }

    /// Effective User-Agent string currently sent on feed/download requests.
    var effectiveUserAgent: String {
        AppUserAgent.resolved(override: customUserAgent)
    }

    /// When true, keep the screen awake (`UIApplication.isIdleTimerDisabled`) while playback is actively playing.
    /// Default off (battery-friendly). Does not override Low Power Mode system behavior beyond the idle timer; no brightness hacks; PiP / background audio unchanged.
    @Published var keepScreenOnWhilePlaying: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOnWhilePlaying, forKey: Keys.keepScreenOnWhilePlaying)
        }
    }

    /// When true, finishing an episode auto-advances to `nextQueueEpisode` (**Queue only** — not the next episode of the same feed). Default on.
    /// When off, episode end still saves progress / marks played (same as today) but does not start the next queue item.
    /// End-of-episode sleep timer always stops without advancing (unchanged).
    @Published var continuousPlaybackEnabled: Bool {
        didSet {
            UserDefaults.standard.set(continuousPlaybackEnabled, forKey: Keys.continuousPlaybackEnabled)
        }
    }

    /// When true, `PodcastStore.markPlayed` clears `positionSeconds` to 0 (current default / AntennaPod-like clean resume-from-start).
    /// When false, mark-played keeps the saved playback position (so Mark unplayed can resume). Default **true** — match prior beta.
    @Published var resetPositionWhenMarkedPlayed: Bool {
        didSet {
            UserDefaults.standard.set(resetPositionWhenMarkedPlayed, forKey: Keys.resetPositionWhenMarkedPlayed)
        }
    }

    /// When true, player time labels show remaining (−m:ss) instead of total duration. Default **false** (Android `pref_show_remain_time`).
    /// Mini + full player: left stays position; right shows duration or −remaining. Full player tap on the right label toggles this setting.
    @Published var showRemainingTime: Bool {
        didSet {
            UserDefaults.standard.set(showRemainingTime, forKey: Keys.showRemainingTime)
        }
    }

    /// Seconds to seek backward when resuming after a pause ≥ 1s (0 = off). Default **2**.
    /// Honest beta: fixed amount (not Android `RewindAfterPauseUtils` elapsed tiers). Only after an actual pause of the current item — not cold play / first start.
    @Published var rewindAfterPauseSeconds: Int {
        didSet {
            UserDefaults.standard.set(rewindAfterPauseSeconds, forKey: Keys.rewindAfterPauseSeconds)
        }
    }

    /// Seconds before end that count as “played” when leaving / stopping (Android `prefSmartMarkAsPlayedSecs`, default 30).
    /// Presets Off/15/30/60/120/300/600 + Custom… 1–600. `0` = Off: only natural end (`ended: true`) or explicit mark — not near-end scrub/leave.
    @Published var smartMarkAsPlayedSeconds: Int {
        didSet {
            UserDefaults.standard.set(smartMarkAsPlayedSeconds, forKey: Keys.smartMarkAsPlayedSeconds)
        }
    }

    /// Ordered Home section ids (all known sections; hidden ones stay in order for Settings reorder).
    @Published var homeSectionOrder: [HomeSectionId] {
        didSet {
            UserDefaults.standard.set(
                homeSectionOrder.map(\.rawValue).joined(separator: ","),
                forKey: Keys.homeSectionOrder
            )
        }
    }

    /// Section ids hidden from Home (still listed in Home layout Settings).
    @Published var homeHiddenSections: Set<HomeSectionId> {
        didSet {
            let raw = homeHiddenSections.map(\.rawValue).sorted().joined(separator: ",")
            UserDefaults.standard.set(raw, forKey: Keys.homeHiddenSections)
        }
    }


    /// Subscriptions tab list order: recently updated (default) or alphabetical A–Z. Client-side only.
    @Published var subscriptionsSort: SubscriptionsSort {
        didSet {
            UserDefaults.standard.set(subscriptionsSort.rawValue, forKey: Keys.subscriptionsSort)
        }
    }

    /// Subscriptions category chip filter. Empty string = All; otherwise a feed `itunes:category` text
    /// present in the library (case-insensitive). Default All. Persisted (+ backup). Feeds with empty
    /// categories never match a specific chip. Applied after search, before language / tag filter.
    @Published var subscriptionsCategoryFilter: String {
        didSet {
            UserDefaults.standard.set(subscriptionsCategoryFilter, forKey: Keys.subscriptionsCategoryFilter)
        }
    }

    /// Subscriptions language chip filter. Empty string = All; otherwise a feed-provided language code
    /// present in the library (case-insensitive). Default All. Persisted (+ backup). Feeds with empty
    /// language never match a specific chip. Applied after search → category, before tag filter.
    @Published var subscriptionsLanguageFilter: String {
        didSet {
            UserDefaults.standard.set(subscriptionsLanguageFilter, forKey: Keys.subscriptionsLanguageFilter)
        }
    }

    /// Global default for Feed detail episode list order (`pubDateEpochMs`: newest / oldest).
    /// Per-feed override: `FeedSettings.episodeSort` (nil = Use global). All Episodes uses `allEpisodesSort`; Inbox uses `inboxSort`.
    /// itunes:type is display-only and must not change this.
    @Published var feedEpisodeSort: FeedEpisodeSort {
        didSet {
            UserDefaults.standard.set(feedEpisodeSort.rawValue, forKey: Keys.feedEpisodeSort)
        }
    }


    /// Feed detail chip filter (All / Unplayed / Played). Default All. Persisted globally (not per-feed).
    /// Unplayed matches All Episodes: `!isPlayed` && not archived. Played uses `isPlayed` only (archive ignored).
    /// Applied after `feedEpisodeSort`, before `.searchable`. Bulk Download all / Mark all played stay full-feed.
    @Published var feedEpisodeFilter: FeedEpisodeFilter {
        didSet {
            UserDefaults.standard.set(feedEpisodeFilter.rawValue, forKey: Keys.feedEpisodeFilter)
        }
    }


    /// Inbox tab episode list order by `pubDateEpochMs`: newest first (default) or oldest first.
    /// Missing dates sort last; stable tiebreaker is episode `id` (no `dateAdded` on the model).
    /// Does not change Home New preview (always newest-first from `PodcastStore.inboxEpisodes`); All Episodes uses `allEpisodesSort`.
    @Published var inboxSort: InboxSort {
        didSet {
            UserDefaults.standard.set(inboxSort.rawValue, forKey: Keys.inboxSort)
        }
    }

    /// Inbox podcast chip filter. Empty string = All; otherwise a feed UUID that currently has
    /// (or recently had) Inbox episodes. Default All. Persisted (+ backup). Applied after
    /// `inboxSort`, before library `.searchable` replaces the list. Chips list only feeds
    /// present in the current Inbox catalog (never invent). Orphan inbox items without a
    /// matching library feed match All only. **View-only** — Mark all / Add all to queue /
    /// Archive all / tab badge stay full Inbox.
    @Published var inboxPodcastFilter: String {
        didSet {
            UserDefaults.standard.set(inboxPodcastFilter, forKey: Keys.inboxPodcastFilter)
        }
    }

    /// Downloads tab list order: newest first (default) or oldest first.
    /// Sort key prefers `DownloadedEpisode.downloadedAtEpochMs` (download completion); else episode `pubDateEpochMs`.
    /// Missing dates sort last; stable tiebreaker is episode `id`. Applies to search-filtered results too.
    @Published var downloadsSort: DownloadsSort {
        didSet {
            UserDefaults.standard.set(downloadsSort.rawValue, forKey: Keys.downloadsSort)
        }
    }

    /// Downloads tab chip filter (All / Unplayed / Played via PodcastStore.isPlayed). Default All. Persisted.
    /// Applied before podcast filter and `.searchable`; `downloadsSort` still orders the filtered list.
    @Published var downloadsFilter: DownloadsFilter {
        didSet {
            UserDefaults.standard.set(downloadsFilter.rawValue, forKey: Keys.downloadsFilter)
        }
    }

    /// Downloads podcast chip filter. Empty string = All; otherwise a feed UUID that currently has
    /// (or recently had) downloaded episodes. Default All. Persisted (+ backup). Applied after
    /// played chip, before `.searchable`. Chips list only feeds present in the current download set
    /// (never invent). Orphan downloads without a matching library feed match All only.
    @Published var downloadsPodcastFilter: String {
        didSet {
            UserDefaults.standard.set(downloadsPodcastFilter, forKey: Keys.downloadsPodcastFilter)
        }
    }

    /// History list order by `HistoryEpisode.lastPlayedAtEpochMs`: newest first (default) or oldest first.
    /// That field is `playbackStates.lastPlayedAtEpochMs`, else `updatedAtEpochMs` (same as store History catalog).
    /// Stable tiebreaker is episode `id`. Client-side re-sort in HistoryView only — `PodcastStore.historyEpisodes`
    /// stays newest-first for Home Continue / Clear history counts. Applies to podcast-chip + search-filtered results too.
    @Published var historySort: HistorySort {
        didSet {
            UserDefaults.standard.set(historySort.rawValue, forKey: Keys.historySort)
        }
    }

    /// History podcast chip filter. Empty string = All; otherwise a feed UUID that currently has
    /// (or recently had) history episodes. Default All. Persisted (+ backup). Applied before
    /// `.searchable`; `historySort` still orders the filtered list. Chips list only feeds
    /// present in the current History catalog (never invent). Orphan history items without a
    /// matching library feed match All only. **View-only** — Clear history / Add all to queue
    /// stay full History catalog. Home Continue listening does not follow this chip.
    @Published var historyPodcastFilter: String {
        didSet {
            UserDefaults.standard.set(historyPodcastFilter, forKey: Keys.historyPodcastFilter)
        }
    }

    /// Max History-listed episodes kept in `playback.json` (50 / 100 / 200 / 500 / Unlimited).
    /// Default **Unlimited**. Finite caps trim oldest by `lastPlayedAt` else `updatedAt` (same as History catalog)
    /// on append, load, and Settings change — drops whole `playbackStates` entries (progress + played), same as
    /// Remove from history. Does not touch favorites / archive / downloads / queue. Statistics / Echo / Continue
    /// may lose trimmed episodes. **No separate history.json.**
    @Published var historySizeLimit: HistorySizeLimit {
        didSet {
            UserDefaults.standard.set(historySizeLimit.rawValue, forKey: Keys.historySizeLimit)
        }
    }

    /// Favorites list order by `FavoriteEpisode.favoritedAtEpochMs` (`favorites.json` / `favoriteAtById`):
    /// newest first (default) or oldest first.
    /// Stable tiebreaker is episode `id`. Client-side re-sort in FavoritesView only — `PodcastStore.favoriteEpisodes`
    /// stays newest-first for Home Favorites preview / Clear favorites counts. Applies to podcast-chip + search-filtered results too.
    @Published var favoritesSort: FavoritesSort {
        didSet {
            UserDefaults.standard.set(favoritesSort.rawValue, forKey: Keys.favoritesSort)
        }
    }

    /// Favorites podcast chip filter. Empty string = All; otherwise a feed UUID that currently has
    /// (or recently had) favorite episodes. Default All. Persisted (+ backup). Applied before
    /// `.searchable`; `favoritesSort` still orders the filtered list. Chips list only feeds
    /// present in the current Favorites catalog (never invent). Orphan favorites without a
    /// matching library feed match All only. **View-only** — Clear favorites / Add all to queue
    /// stay full Favorites catalog. Home Favorites preview does not follow this chip.
    @Published var favoritesPodcastFilter: String {
        didSet {
            UserDefaults.standard.set(favoritesPodcastFilter, forKey: Keys.favoritesPodcastFilter)
        }
    }

    /// Archived list order by `ArchivedEpisode.archivedAtEpochMs` (`archived.json` / `archivedAtById`):
    /// newest first (default) or oldest first.
    /// Stable tiebreaker is episode `id`. Client-side re-sort in ArchivedView only — `PodcastStore.archivedEpisodes`
    /// stays newest-first for Restore all counts. Applies to search-filtered results too.
    @Published var archivedSort: ArchivedSort {
        didSet {
            UserDefaults.standard.set(archivedSort.rawValue, forKey: Keys.archivedSort)
        }
    }

    /// Library → Episodes chip filter (All / Unplayed / Downloaded / Favorites). Default All. Persisted.
    @Published var allEpisodesFilter: AllEpisodesFilter {
        didSet {
            UserDefaults.standard.set(allEpisodesFilter.rawValue, forKey: Keys.allEpisodesFilter)
        }
    }

    /// Library → Episodes list order by `pubDateEpochMs`: newest first (default) or oldest first.
    /// **Soft-cap honesty:** `PodcastStore.allEpisodes` is already the newest-500; Oldest only
    /// reorders within that capped set (does not surface older episodes beyond the limit).
    /// Missing dates sort last; stable tiebreaker episode `id`. Pipeline: soft cap → sort → chip → search.
    /// Client-side re-sort in AllEpisodesView only — store catalog stays newest-first.
    @Published var allEpisodesSort: AllEpisodesSort {
        didSet {
            UserDefaults.standard.set(allEpisodesSort.rawValue, forKey: Keys.allEpisodesSort)
        }
    }

    /// When true, Queue tab disables Edit drag reorder, Shuffle, Shuffle (keep playing first), Reverse order, Sort by date, Sort by duration, Move playing to top, and EpisodeRow Move to top/bottom.
    /// Default **false** (unlocked). Enqueue / Play Next / Remove / Clear queue stay available (reorder lock only).
    /// Mirrors Android `prefQueueLocked` / `UserPreferences.isQueueLocked()`.
    @Published var queueLocked: Bool {
        didSet {
            UserDefaults.standard.set(queueLocked, forKey: Keys.queueLocked)
        }
    }

    /// Queue tab chip filter (All / Unplayed / Played via PodcastStore.isPlayed). Default All. Persisted.
    /// Applied before podcast filter and `.searchable`. Chip ≠ All, podcast ≠ All, or non-empty search disables
    /// Edit/`.onMove` like search alone — filtered indices would not map to the persisted queue.
    /// Move to top/bottom still uses episode id → full queue.
    /// Shuffle / Shuffle (keep playing first) / Reverse order / Sort by date / Sort by duration / Clear queue / Play Next stay full-queue scoped (Shuffle variants/Reverse/Sort still need unlock + count ≥ 2).
    @Published var queueFilter: QueueFilter {
        didSet {
            UserDefaults.standard.set(queueFilter.rawValue, forKey: Keys.queueFilter)
        }
    }

    /// Queue podcast chip filter. Empty string = All; otherwise a feed UUID that currently has
    /// (or recently had) queued episodes. Default All. Persisted (+ backup). Applied after
    /// played chip, before `.searchable`. Chips list only feeds present in the current queue
    /// (never invent). Orphan queue items without a matching library feed match All only.
    /// View-only — does not remove episodes from the persisted queue.
    @Published var queuePodcastFilter: String {
        didSet {
            UserDefaults.standard.set(queuePodcastFilter, forKey: Keys.queuePodcastFilter)
        }
    }

    /// Statistics / Echo time range: This week / This month / This year / All time (default).
    /// Filters aggregations by `lastPlayedAt` (else `updatedAt`) within the device-calendar unit.
    /// Shared by Statistics and Echo; persisted + backup. Coarse episode stamps — not per-session listen windows.
    @Published var statisticsTimeRange: StatisticsTimeRange {
        didSet {
            UserDefaults.standard.set(statisticsTimeRange.rawValue, forKey: Keys.statisticsTimeRange)
        }
    }

    /// Statistics / Echo reset baseline (epoch ms). `0` = no baseline (count all saved progress).
    /// **Honest:** does **not** clear History / progress / played flags — only filters aggregations
    /// to stamps ≥ this value (coarse `lastPlayedAt` else `updatedAt`). Persisted + backup.
    /// Unlike Android there is no separate `played_duration` counter; this is the iOS equivalent.
    @Published var statisticsResetAtEpochMs: Int64 {
        didSet {
            UserDefaults.standard.set(Double(statisticsResetAtEpochMs), forKey: Keys.statisticsResetAtEpochMs)
        }
    }

    /// Set Statistics / Echo baseline to `now` (Android reset-statistics spirit without wiping History).
    func resetStatisticsBaseline(at date: Date = Date()) {
        statisticsResetAtEpochMs = Int64(date.timeIntervalSince1970 * 1000)
    }

    /// Visible sections in display order (hidden filtered out).
    var visibleHomeSections: [HomeSectionId] {
        homeSectionOrder.filter { !homeHiddenSections.contains($0) }
    }

    func isHomeSectionVisible(_ id: HomeSectionId) -> Bool {
        !homeHiddenSections.contains(id)
    }

    func setHomeSectionVisible(_ id: HomeSectionId, _ visible: Bool) {
        var next = homeHiddenSections
        if visible {
            next.remove(id)
        } else {
            next.insert(id)
        }
        homeHiddenSections = next
    }

    func moveHomeSection(from source: IndexSet, to destination: Int) {
        var order = homeSectionOrder
        order.move(fromOffsets: source, toOffset: destination)
        homeSectionOrder = order
    }

    func resetHomeLayout() {
        homeSectionOrder = HomeSectionId.defaultOrder
        homeHiddenSections = HomeSectionId.defaultHidden
    }

    /// Resolved ISO country used for chart requests.
    var resolvedChartsCountryCode: String {
        let pref = ChartsCountryPreference.fromStorage(chartsCountryCode)
        switch pref {
        case .automatic:
            return ItunesTopListService.defaultCountryCode()
        case .code(let c):
            return c
        }
    }

    init() {
        let themeRaw = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.system.rawValue
        theme = AppTheme(rawValue: themeRaw) ?? .system
        let accentRaw = UserDefaults.standard.string(forKey: Keys.accentColor) ?? AppAccentColor.system.rawValue
        accentColor = AppAccentColor(rawValue: accentRaw) ?? .system
        if UserDefaults.standard.object(forKey: Keys.defaultPlaybackSpeed) != nil {
            let stored = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
            // Presets or Custom… (0.5–3.0); out-of-range → 1.0.
            if Self.speedPresets.contains(stored) {
                defaultPlaybackSpeed = stored
            } else if PlaybackService.customPlaybackSpeedRange.contains(stored) {
                defaultPlaybackSpeed = PlaybackService.clampPlaybackSpeed(stored)
            } else {
                defaultPlaybackSpeed = 1.0
            }
        } else {
            defaultPlaybackSpeed = 1.0
        }
        downloadStorageLimit = Self.loadStorageLimit()
        let intervalRaw = UserDefaults.standard.string(forKey: Keys.refreshInterval)
            ?? FeedRefreshInterval.manual.rawValue
        refreshInterval = FeedRefreshInterval(rawValue: intervalRaw) ?? .manual
        if UserDefaults.standard.object(forKey: Keys.lastFeedRefreshAt) != nil {
            let epoch = UserDefaults.standard.double(forKey: Keys.lastFeedRefreshAt)
            lastFeedRefreshAt = Date(timeIntervalSince1970: epoch)
        } else {
            lastFeedRefreshAt = nil
        }
        let actionRaw = UserDefaults.standard.string(forKey: Keys.newEpisodeAction)
            ?? NewEpisodeAction.inboxOnly.rawValue
        newEpisodeAction = NewEpisodeAction(rawValue: actionRaw) ?? .inboxOnly
        if UserDefaults.standard.object(forKey: Keys.autoDownloadEnabled) != nil {
            autoDownloadEnabled = UserDefaults.standard.bool(forKey: Keys.autoDownloadEnabled)
        } else {
            autoDownloadEnabled = false
        }
        let perFeedRaw = UserDefaults.standard.object(forKey: Keys.autoDownloadEpisodesPerFeed) as? Int
            ?? AutoDownloadEpisodesPerFeed.two.rawValue
        autoDownloadEpisodesPerFeed = AutoDownloadEpisodesPerFeed(rawValue: perFeedRaw) ?? .two
        let parallelRaw = UserDefaults.standard.object(forKey: Keys.maxParallelDownloads) as? Int
            ?? MaxParallelDownloads.three.rawValue
        maxParallelDownloads = MaxParallelDownloads(rawValue: parallelRaw) ?? .three
        let cacheRaw = UserDefaults.standard.object(forKey: Keys.downloadEpisodeCacheLimit) as? Int
            ?? DownloadEpisodeCacheLimit.unlimited.rawValue
        downloadEpisodeCacheLimit = DownloadEpisodeCacheLimit(rawValue: cacheRaw) ?? .unlimited
        if UserDefaults.standard.object(forKey: Keys.autoDownloadWifiOnly) != nil {
            autoDownloadWifiOnly = UserDefaults.standard.bool(forKey: Keys.autoDownloadWifiOnly)
        } else {
            autoDownloadWifiOnly = true
        }
        if UserDefaults.standard.object(forKey: Keys.manualDownloadWifiOnly) != nil {
            manualDownloadWifiOnly = UserDefaults.standard.bool(forKey: Keys.manualDownloadWifiOnly)
        } else {
            manualDownloadWifiOnly = false
        }
        if UserDefaults.standard.object(forKey: Keys.streamWifiOnly) != nil {
            streamWifiOnly = UserDefaults.standard.bool(forKey: Keys.streamWifiOnly)
        } else {
            streamWifiOnly = false
        }
        let sourceRaw = UserDefaults.standard.string(forKey: Keys.playbackSourcePreference)
            ?? PlaybackSourcePreference.automatic.rawValue
        playbackSourcePreference = PlaybackSourcePreference(rawValue: sourceRaw) ?? .automatic
        if UserDefaults.standard.object(forKey: Keys.autoDeleteAfterPlaying) != nil {
            autoDeleteAfterPlaying = UserDefaults.standard.bool(forKey: Keys.autoDeleteAfterPlaying)
        } else {
            autoDeleteAfterPlaying = false
        }
        rewindSeconds = Self.loadSkipSeconds(
            key: Keys.rewindSeconds,
            defaultValue: Self.defaultRewindSeconds
        )
        fastForwardSeconds = Self.loadSkipSeconds(
            key: Keys.fastForwardSeconds,
            defaultValue: Self.defaultFastForwardSeconds
        )
        skipIntroSeconds = Self.loadSkipIntroOutroSeconds(key: Keys.skipIntroSeconds)
        skipOutroSeconds = Self.loadSkipIntroOutroSeconds(key: Keys.skipOutroSeconds)
        if UserDefaults.standard.object(forKey: Keys.notifyOnNewEpisodes) != nil {
            notifyOnNewEpisodes = UserDefaults.standard.bool(forKey: Keys.notifyOnNewEpisodes)
        } else {
            // Default off; opt-in + permission gate (honest if denied).
            notifyOnNewEpisodes = false
        }
        if UserDefaults.standard.object(forKey: Keys.notifyOnDownloadErrors) != nil {
            notifyOnDownloadErrors = UserDefaults.standard.bool(forKey: Keys.notifyOnDownloadErrors)
        } else {
            // Default on; same permission gate as new-episode alerts.
            notifyOnDownloadErrors = true
        }
        if UserDefaults.standard.object(forKey: Keys.notifyOnSyncErrors) != nil {
            notifyOnSyncErrors = UserDefaults.standard.bool(forKey: Keys.notifyOnSyncErrors)
        } else {
            // Default on; same permission gate as new-episode / download-error alerts.
            notifyOnSyncErrors = true
        }
        if UserDefaults.standard.object(forKey: Keys.notifyOnSleepTimerEnd) != nil {
            notifyOnSleepTimerEnd = UserDefaults.standard.bool(forKey: Keys.notifyOnSleepTimerEnd)
        } else {
            // Default on; same permission gate as DL / sync error alerts.
            notifyOnSleepTimerEnd = true
        }
        lastCustomSleepTimerMinutes = Self.loadLastCustomSleepTimerMinutes()
        if UserDefaults.standard.object(forKey: Keys.askForAppStoreRating) != nil {
            askForAppStoreRating = UserDefaults.standard.bool(forKey: Keys.askForAppStoreRating)
        } else {
            askForAppStoreRating = true
        }
        if UserDefaults.standard.object(forKey: Keys.playVideoAsAudioOnly) != nil {
            playVideoAsAudioOnly = UserDefaults.standard.bool(forKey: Keys.playVideoAsAudioOnly)
        } else {
            // Default off: show video surface when the episode is video.
            playVideoAsAudioOnly = false
        }
        if UserDefaults.standard.object(forKey: Keys.volumeAdaptationEnabled) != nil {
            volumeAdaptationEnabled = UserDefaults.standard.bool(forKey: Keys.volumeAdaptationEnabled)
        } else {
            // Default off: use .default / .moviePlayback session mode (not spokenAudio).
            volumeAdaptationEnabled = false
        }
        if UserDefaults.standard.object(forKey: Keys.skipSilenceEnabled) != nil {
            skipSilenceEnabled = UserDefaults.standard.bool(forKey: Keys.skipSilenceEnabled)
        } else {
            // Default off; preference only — PlaybackService does not skip silence on AVPlayer.
            skipSilenceEnabled = false
        }
        if UserDefaults.standard.object(forKey: Keys.stereoToMonoEnabled) != nil {
            stereoToMonoEnabled = UserDefaults.standard.bool(forKey: Keys.stereoToMonoEnabled)
        } else {
            // Default off: leave preferred output channel count alone (stereo routes stay stereo).
            stereoToMonoEnabled = false
        }
        if UserDefaults.standard.object(forKey: Keys.preservePitchEnabled) != nil {
            preservePitchEnabled = UserDefaults.standard.bool(forKey: Keys.preservePitchEnabled)
        } else {
            // Default on: speech-friendly pitch correction (AVPlayerItem .timeDomain).
            preservePitchEnabled = true
        }
        customUserAgent = AppUserAgent.sanitize(
            UserDefaults.standard.string(forKey: Keys.customUserAgent) ?? ""
        )
        if UserDefaults.standard.object(forKey: Keys.keepScreenOnWhilePlaying) != nil {
            keepScreenOnWhilePlaying = UserDefaults.standard.bool(forKey: Keys.keepScreenOnWhilePlaying)
        } else {
            // Default off: allow normal idle lock (battery-friendly).
            keepScreenOnWhilePlaying = false
        }
        if UserDefaults.standard.object(forKey: Keys.continuousPlaybackEnabled) != nil {
            continuousPlaybackEnabled = UserDefaults.standard.bool(forKey: Keys.continuousPlaybackEnabled)
        } else {
            // Default on: auto-advance to next queue episode on end (AntennaPod continuous playback).
            continuousPlaybackEnabled = true
        }
        if UserDefaults.standard.object(forKey: Keys.resetPositionWhenMarkedPlayed) != nil {
            resetPositionWhenMarkedPlayed = UserDefaults.standard.bool(forKey: Keys.resetPositionWhenMarkedPlayed)
        } else {
            // Default on: clear position on mark-played (prior beta / AntennaPod-like).
            resetPositionWhenMarkedPlayed = true
        }
        if UserDefaults.standard.object(forKey: Keys.showRemainingTime) != nil {
            showRemainingTime = UserDefaults.standard.bool(forKey: Keys.showRemainingTime)
        } else {
            // Default off: show total duration (Android pref_show_remain_time unchecked).
            showRemainingTime = false
        }
        rewindAfterPauseSeconds = Self.loadRewindAfterPauseSeconds()
        smartMarkAsPlayedSeconds = Self.loadSmartMarkAsPlayedSeconds()
        let chartsRaw = UserDefaults.standard.string(forKey: Keys.chartsCountryCode) ?? "auto"
        chartsCountryCode = ChartsCountryPreference.fromStorage(chartsRaw).storageValue
        homeSectionOrder = Self.loadHomeSectionOrder()
        homeHiddenSections = Self.loadHomeHiddenSections()
        let sortRaw = UserDefaults.standard.string(forKey: Keys.subscriptionsSort)
            ?? SubscriptionsSort.recentlyUpdated.rawValue
        subscriptionsSort = SubscriptionsSort(rawValue: sortRaw) ?? .recentlyUpdated
        let catFilterRaw = UserDefaults.standard.string(forKey: Keys.subscriptionsCategoryFilter) ?? ""
        subscriptionsCategoryFilter = SubscriptionCategoryFilter.fromStorage(catFilterRaw).storageValue
        let langFilterRaw = UserDefaults.standard.string(forKey: Keys.subscriptionsLanguageFilter) ?? ""
        subscriptionsLanguageFilter = SubscriptionLanguageFilter.fromStorage(langFilterRaw).storageValue
        let feedEpSortRaw = UserDefaults.standard.string(forKey: Keys.feedEpisodeSort)
            ?? FeedEpisodeSort.newestFirst.rawValue
        feedEpisodeSort = FeedEpisodeSort(rawValue: feedEpSortRaw) ?? .newestFirst
        let feedEpFilterRaw = UserDefaults.standard.string(forKey: Keys.feedEpisodeFilter)
            ?? FeedEpisodeFilter.all.rawValue
        feedEpisodeFilter = FeedEpisodeFilter(rawValue: feedEpFilterRaw) ?? .all
        let inboxSortRaw = UserDefaults.standard.string(forKey: Keys.inboxSort)
            ?? InboxSort.newestFirst.rawValue
        inboxSort = InboxSort(rawValue: inboxSortRaw) ?? .newestFirst
        let inboxPodcastFilterRaw = UserDefaults.standard.string(forKey: Keys.inboxPodcastFilter) ?? ""
        inboxPodcastFilter = InboxPodcastFilter.fromStorage(inboxPodcastFilterRaw).storageValue
        let downloadsSortRaw = UserDefaults.standard.string(forKey: Keys.downloadsSort)
            ?? DownloadsSort.newestFirst.rawValue
        downloadsSort = DownloadsSort(rawValue: downloadsSortRaw) ?? .newestFirst
        let downloadsFilterRaw = UserDefaults.standard.string(forKey: Keys.downloadsFilter)
            ?? DownloadsFilter.all.rawValue
        downloadsFilter = DownloadsFilter(rawValue: downloadsFilterRaw) ?? .all
        let downloadsPodcastFilterRaw = UserDefaults.standard.string(forKey: Keys.downloadsPodcastFilter) ?? ""
        downloadsPodcastFilter = DownloadsPodcastFilter.fromStorage(downloadsPodcastFilterRaw).storageValue
        let historySortRaw = UserDefaults.standard.string(forKey: Keys.historySort)
            ?? HistorySort.newestFirst.rawValue
        historySort = HistorySort(rawValue: historySortRaw) ?? .newestFirst
        let historyPodcastFilterRaw = UserDefaults.standard.string(forKey: Keys.historyPodcastFilter) ?? ""
        historyPodcastFilter = HistoryPodcastFilter.fromStorage(historyPodcastFilterRaw).storageValue
        let historyLimitRaw = UserDefaults.standard.object(forKey: Keys.historySizeLimit) as? Int
            ?? HistorySizeLimit.unlimited.rawValue
        historySizeLimit = HistorySizeLimit(rawValue: historyLimitRaw) ?? .unlimited
        let favoritesSortRaw = UserDefaults.standard.string(forKey: Keys.favoritesSort)
            ?? FavoritesSort.newestFirst.rawValue
        favoritesSort = FavoritesSort(rawValue: favoritesSortRaw) ?? .newestFirst
        let favoritesPodcastFilterRaw = UserDefaults.standard.string(forKey: Keys.favoritesPodcastFilter) ?? ""
        favoritesPodcastFilter = FavoritesPodcastFilter.fromStorage(favoritesPodcastFilterRaw).storageValue
        let archivedSortRaw = UserDefaults.standard.string(forKey: Keys.archivedSort)
            ?? ArchivedSort.newestFirst.rawValue
        archivedSort = ArchivedSort(rawValue: archivedSortRaw) ?? .newestFirst
        let episodesFilterRaw = UserDefaults.standard.string(forKey: Keys.allEpisodesFilter)
            ?? AllEpisodesFilter.all.rawValue
        allEpisodesFilter = AllEpisodesFilter(rawValue: episodesFilterRaw) ?? .all
        let episodesSortRaw = UserDefaults.standard.string(forKey: Keys.allEpisodesSort)
            ?? AllEpisodesSort.newestFirst.rawValue
        allEpisodesSort = AllEpisodesSort(rawValue: episodesSortRaw) ?? .newestFirst
        if UserDefaults.standard.object(forKey: Keys.queueLocked) != nil {
            queueLocked = UserDefaults.standard.bool(forKey: Keys.queueLocked)
        } else {
            // Default unlocked (Android prefQueueLocked default false).
            queueLocked = false
        }
        let queueFilterRaw = UserDefaults.standard.string(forKey: Keys.queueFilter)
            ?? QueueFilter.all.rawValue
        queueFilter = QueueFilter(rawValue: queueFilterRaw) ?? .all
        let queuePodcastFilterRaw = UserDefaults.standard.string(forKey: Keys.queuePodcastFilter) ?? ""
        queuePodcastFilter = QueuePodcastFilter.fromStorage(queuePodcastFilterRaw).storageValue
        let statsRangeRaw = UserDefaults.standard.string(forKey: Keys.statisticsTimeRange)
            ?? StatisticsTimeRange.allTime.rawValue
        statisticsTimeRange = StatisticsTimeRange(rawValue: statsRangeRaw) ?? .allTime
        if UserDefaults.standard.object(forKey: Keys.statisticsResetAtEpochMs) != nil {
            statisticsResetAtEpochMs = Int64(UserDefaults.standard.double(forKey: Keys.statisticsResetAtEpochMs))
        } else {
            statisticsResetAtEpochMs = 0
        }
    }

    /// `true` when interval is not manual and enough time has passed since the last refresh
    /// (or never refreshed yet).
    var isFeedRefreshDue: Bool {
        guard let interval = refreshInterval.timeInterval else { return false }
        guard let last = lastFeedRefreshAt else { return true }
        return Date().timeIntervalSince(last) >= interval
    }

    /// Record a completed full refresh so the next due-check starts from now.
    func markFeedRefreshCompleted(at date: Date = Date()) {
        lastFeedRefreshAt = date
    }

    /// Apply a custom MB budget from the Settings stepper / text field.
    func setCustomStorageLimitMegabytes(_ megabytes: Int) {
        let clamped = min(max(megabytes, Self.customStorageMBRange.lowerBound), Self.customStorageMBRange.upperBound)
        downloadStorageLimit = .customMegabytes(clamped)
    }

    private func persistStorageLimit() {
        switch downloadStorageLimit {
        case .unlimited:
            UserDefaults.standard.set(Kind.unlimited.rawValue, forKey: Keys.storageLimitKind)
            UserDefaults.standard.removeObject(forKey: Keys.storageLimitValue)
        case .gigabytes(let gb):
            UserDefaults.standard.set(Kind.gigabytes.rawValue, forKey: Keys.storageLimitKind)
            UserDefaults.standard.set(gb, forKey: Keys.storageLimitValue)
        case .customMegabytes(let mb):
            UserDefaults.standard.set(Kind.customMegabytes.rawValue, forKey: Keys.storageLimitKind)
            UserDefaults.standard.set(mb, forKey: Keys.storageLimitValue)
        }
    }

    /// Clamp persisted / backup Custom… sleep minutes into `PlaybackService.customSleepTimerMinutesRange`.
    private static func loadLastCustomSleepTimerMinutes() -> Int {
        let range = PlaybackService.customSleepTimerMinutesRange
        let fallback = defaultLastCustomSleepTimerMinutes
        guard UserDefaults.standard.object(forKey: Keys.lastCustomSleepTimerMinutes) != nil else {
            return fallback
        }
        let stored = UserDefaults.standard.integer(forKey: Keys.lastCustomSleepTimerMinutes)
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    /// Presets or Custom… (5–60); out-of-range → default.
    private static func loadSkipSeconds(key: String, defaultValue: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultValue
        }
        let stored = UserDefaults.standard.integer(forKey: key)
        if skipIntervalPresets.contains(stored) {
            return stored
        }
        let range = PlaybackService.customSkipIntervalSecondsRange
        if range.contains(stored) {
            return stored
        }
        return defaultValue
    }

    /// Accept presets or Custom… range; otherwise `defaultValue`.
    private static func clampSkipSeconds(_ value: Int, defaultValue: Int) -> Int {
        if skipIntervalPresets.contains(value) {
            return value
        }
        let range = PlaybackService.customSkipIntervalSecondsRange
        if range.contains(value) {
            return value
        }
        return defaultValue
    }

    private static func loadSkipIntroOutroSeconds(key: String) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return defaultSkipIntroOutroSeconds
        }
        let stored = UserDefaults.standard.integer(forKey: key)
        return skipIntroOutroPresets.contains(stored) ? stored : defaultSkipIntroOutroSeconds
    }

    /// Label for Settings pickers (`Off` when 0).
    static func skipIntroOutroLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds) seconds"
    }

    /// Label for smart-mark Settings picker (`Off` when 0); uses String Catalog.
    /// Android-like: ≥60 and divisible by 60 → minutes; else seconds (Custom…).
    static func smartMarkAsPlayedLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            return String(localized: "Off")
        case 15:
            return String(localized: "15 seconds")
        case 30:
            return String(localized: "30 seconds")
        case 60:
            return String(localized: "1 minute")
        case 120:
            return String(localized: "2 minutes")
        case 300:
            return String(localized: "5 minutes")
        case 600:
            return String(localized: "10 minutes")
        default:
            if seconds >= 60, seconds % 60 == 0 {
                let minutes = seconds / 60
                return String(localized: "\(minutes) minutes")
            }
            return String(localized: "\(seconds) seconds")
        }
    }

    /// Label for rewind-after-pause Settings picker (`Off` when 0).
    static func rewindAfterPauseLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0:
            return String(localized: "Off")
        case 1:
            return String(localized: "1 second")
        case 2:
            return String(localized: "2 seconds")
        case 3:
            return String(localized: "3 seconds")
        case 5:
            return String(localized: "5 seconds")
        case 10:
            return String(localized: "10 seconds")
        default:
            return "\(seconds) seconds"
        }
    }

    /// Presets or Custom… (1–600); out-of-range → default 30. Off (0) is a preset.
    private static func loadSmartMarkAsPlayedSeconds() -> Int {
        guard UserDefaults.standard.object(forKey: Keys.smartMarkAsPlayedSeconds) != nil else {
            return defaultSmartMarkAsPlayedSeconds
        }
        let stored = UserDefaults.standard.integer(forKey: Keys.smartMarkAsPlayedSeconds)
        return clampSmartMarkAsPlayedSeconds(stored)
    }

    /// Accept presets (incl. Off) or Custom… 1–600; otherwise default 30.
    private static func clampSmartMarkAsPlayedSeconds(_ value: Int) -> Int {
        if smartMarkAsPlayedPresets.contains(value) {
            return value
        }
        let range = PlaybackService.customSmartMarkAsPlayedSecondsRange
        if range.contains(value) {
            return value
        }
        return defaultSmartMarkAsPlayedSeconds
    }

    private static func loadRewindAfterPauseSeconds() -> Int {
        guard UserDefaults.standard.object(forKey: Keys.rewindAfterPauseSeconds) != nil else {
            return defaultRewindAfterPauseSeconds
        }
        let stored = UserDefaults.standard.integer(forKey: Keys.rewindAfterPauseSeconds)
        return rewindAfterPausePresets.contains(stored) ? stored : defaultRewindAfterPauseSeconds
    }


    private static func loadHomeSectionOrder() -> [HomeSectionId] {
        let raw = UserDefaults.standard.string(forKey: Keys.homeSectionOrder) ?? ""
        let parsed = raw.split(separator: ",").compactMap { HomeSectionId(rawValue: String($0)) }
        var order: [HomeSectionId] = []
        var seen = Set<HomeSectionId>()
        for id in parsed where !seen.contains(id) {
            order.append(id)
            seen.insert(id)
        }
        for id in HomeSectionId.defaultOrder where !seen.contains(id) {
            order.append(id)
            seen.insert(id)
        }
        // Drop unknown leftovers already handled; ensure every CaseIterable id present.
        for id in HomeSectionId.allCases where !seen.contains(id) {
            order.append(id)
        }
        return order
    }

    private static func loadHomeHiddenSections() -> Set<HomeSectionId> {
        guard UserDefaults.standard.object(forKey: Keys.homeHiddenSections) != nil else {
            return HomeSectionId.defaultHidden
        }
        let raw = UserDefaults.standard.string(forKey: Keys.homeHiddenSections) ?? ""
        let parsed = Set(raw.split(separator: ",").compactMap { HomeSectionId(rawValue: String($0)) })
        // Ignore ids that are no longer known.
        return parsed.intersection(Set(HomeSectionId.allCases))
    }

    private static func loadStorageLimit() -> DownloadStorageLimit {
        let kindRaw = UserDefaults.standard.string(forKey: Keys.storageLimitKind) ?? Kind.unlimited.rawValue
        let value = UserDefaults.standard.integer(forKey: Keys.storageLimitValue)
        switch Kind(rawValue: kindRaw) {
        case .unlimited, .none:
            return .unlimited
        case .gigabytes:
            let gb = [1, 5, 10].contains(value) ? value : 5
            return .gigabytes(gb)
        case .customMegabytes:
            let mb = value > 0 ? value : 500
            return .customMegabytes(mb)
        }
    }

    // MARK: - Data backup

    /// Snapshot of UserDefaults-backed prefs for iOS JSON backup (no Keychain).
    func backupSnapshot() -> AppSettingsBackupSnapshot {
        let storageKind: String
        let storageValue: Int?
        switch downloadStorageLimit {
        case .unlimited:
            storageKind = Kind.unlimited.rawValue
            storageValue = nil
        case .gigabytes(let gb):
            storageKind = Kind.gigabytes.rawValue
            storageValue = gb
        case .customMegabytes(let mb):
            storageKind = Kind.customMegabytes.rawValue
            storageValue = mb
        }
        return AppSettingsBackupSnapshot(
            theme: theme.rawValue,
            accentColor: accentColor.rawValue,
            defaultPlaybackSpeed: defaultPlaybackSpeed,
            storageLimitKind: storageKind,
            storageLimitValue: storageValue,
            refreshInterval: refreshInterval.rawValue,
            lastFeedRefreshAtEpoch: lastFeedRefreshAt?.timeIntervalSince1970,
            newEpisodeAction: newEpisodeAction.rawValue,
            autoDownloadEnabled: autoDownloadEnabled,
            autoDownloadEpisodesPerFeed: autoDownloadEpisodesPerFeed.rawValue,
            maxParallelDownloads: maxParallelDownloads.rawValue,
            downloadEpisodeCacheLimit: downloadEpisodeCacheLimit.rawValue,
            autoDownloadWifiOnly: autoDownloadWifiOnly,
            manualDownloadWifiOnly: manualDownloadWifiOnly,
            streamWifiOnly: streamWifiOnly,
            playbackSourcePreference: playbackSourcePreference.rawValue,
            autoDeleteAfterPlaying: autoDeleteAfterPlaying,
            rewindSeconds: rewindSeconds,
            fastForwardSeconds: fastForwardSeconds,
            skipIntroSeconds: skipIntroSeconds,
            skipOutroSeconds: skipOutroSeconds,
            notifyOnNewEpisodes: notifyOnNewEpisodes,
            notifyOnDownloadErrors: notifyOnDownloadErrors,
            notifyOnSyncErrors: notifyOnSyncErrors,
            notifyOnSleepTimerEnd: notifyOnSleepTimerEnd,
            lastCustomSleepTimerMinutes: lastCustomSleepTimerMinutes,
            askForAppStoreRating: askForAppStoreRating,
            playVideoAsAudioOnly: playVideoAsAudioOnly,
            volumeAdaptationEnabled: volumeAdaptationEnabled,
            skipSilenceEnabled: skipSilenceEnabled,
            stereoToMonoEnabled: stereoToMonoEnabled,
            preservePitchEnabled: preservePitchEnabled,
            customUserAgent: customUserAgent,
            keepScreenOnWhilePlaying: keepScreenOnWhilePlaying,
            continuousPlaybackEnabled: continuousPlaybackEnabled,
            resetPositionWhenMarkedPlayed: resetPositionWhenMarkedPlayed,
            showRemainingTime: showRemainingTime,
            rewindAfterPauseSeconds: rewindAfterPauseSeconds,
            smartMarkAsPlayedSeconds: smartMarkAsPlayedSeconds,
            chartsCountryCode: chartsCountryCode,
            homeSectionOrder: homeSectionOrder.map(\.rawValue),
            homeHiddenSections: homeHiddenSections.map(\.rawValue).sorted(),
            subscriptionsSort: subscriptionsSort.rawValue,
            subscriptionsCategoryFilter: subscriptionsCategoryFilter,
            subscriptionsLanguageFilter: subscriptionsLanguageFilter,
            feedEpisodeSort: feedEpisodeSort.rawValue,
            feedEpisodeFilter: feedEpisodeFilter.rawValue,
            inboxSort: inboxSort.rawValue,
            inboxPodcastFilter: inboxPodcastFilter,
            downloadsSort: downloadsSort.rawValue,
            downloadsFilter: downloadsFilter.rawValue,
            downloadsPodcastFilter: downloadsPodcastFilter,
            historySort: historySort.rawValue,
            historyPodcastFilter: historyPodcastFilter,
            historySizeLimit: historySizeLimit.rawValue,
            favoritesSort: favoritesSort.rawValue,
            favoritesPodcastFilter: favoritesPodcastFilter,
            archivedSort: archivedSort.rawValue,
            allEpisodesFilter: allEpisodesFilter.rawValue,
            allEpisodesSort: allEpisodesSort.rawValue,
            queueLocked: queueLocked,
            queueFilter: queueFilter.rawValue,
            queuePodcastFilter: queuePodcastFilter,
            statisticsTimeRange: statisticsTimeRange.rawValue,
            statisticsResetAtEpochMs: statisticsResetAtEpochMs
        )
    }

    /// Apply prefs from an iOS JSON backup (writes through didSet → UserDefaults).
    func applyBackupSnapshot(_ snap: AppSettingsBackupSnapshot) {
        theme = AppTheme(rawValue: snap.theme) ?? .system
        if let accentRaw = snap.accentColor {
            accentColor = AppAccentColor(rawValue: accentRaw) ?? .system
        }
        let snapSpeed = snap.defaultPlaybackSpeed
        if AppSettings.speedPresets.contains(snapSpeed) {
            defaultPlaybackSpeed = snapSpeed
        } else if PlaybackService.customPlaybackSpeedRange.contains(snapSpeed) {
            defaultPlaybackSpeed = PlaybackService.clampPlaybackSpeed(snapSpeed)
        }
        switch Kind(rawValue: snap.storageLimitKind) {
        case .unlimited, .none:
            downloadStorageLimit = .unlimited
        case .gigabytes:
            let gb = snap.storageLimitValue ?? 5
            downloadStorageLimit = .gigabytes([1, 5, 10].contains(gb) ? gb : 5)
        case .customMegabytes:
            let mb = snap.storageLimitValue ?? 500
            downloadStorageLimit = .customMegabytes(mb)
        }
        refreshInterval = FeedRefreshInterval(rawValue: snap.refreshInterval) ?? .manual
        if let epoch = snap.lastFeedRefreshAtEpoch {
            lastFeedRefreshAt = Date(timeIntervalSince1970: epoch)
        } else {
            lastFeedRefreshAt = nil
        }
        newEpisodeAction = NewEpisodeAction(rawValue: snap.newEpisodeAction ?? "") ?? .inboxOnly
        autoDownloadEnabled = snap.autoDownloadEnabled
        autoDownloadEpisodesPerFeed =
            AutoDownloadEpisodesPerFeed(rawValue: snap.autoDownloadEpisodesPerFeed) ?? .two
        maxParallelDownloads =
            MaxParallelDownloads(rawValue: snap.maxParallelDownloads ?? MaxParallelDownloads.three.rawValue) ?? .three
        downloadEpisodeCacheLimit =
            DownloadEpisodeCacheLimit(rawValue: snap.downloadEpisodeCacheLimit ?? DownloadEpisodeCacheLimit.unlimited.rawValue)
            ?? .unlimited
        autoDownloadWifiOnly = snap.autoDownloadWifiOnly
        manualDownloadWifiOnly = snap.manualDownloadWifiOnly
        streamWifiOnly = snap.streamWifiOnly
        playbackSourcePreference =
            PlaybackSourcePreference(rawValue: snap.playbackSourcePreference) ?? .automatic
        autoDeleteAfterPlaying = snap.autoDeleteAfterPlaying
        rewindSeconds = Self.clampSkipSeconds(snap.rewindSeconds, defaultValue: Self.defaultRewindSeconds)
        fastForwardSeconds = Self.clampSkipSeconds(snap.fastForwardSeconds, defaultValue: Self.defaultFastForwardSeconds)
        if AppSettings.skipIntroOutroPresets.contains(snap.skipIntroSeconds) {
            skipIntroSeconds = snap.skipIntroSeconds
        }
        if AppSettings.skipIntroOutroPresets.contains(snap.skipOutroSeconds) {
            skipOutroSeconds = snap.skipOutroSeconds
        }
        notifyOnNewEpisodes = snap.notifyOnNewEpisodes
        notifyOnDownloadErrors = snap.notifyOnDownloadErrors
        notifyOnSyncErrors = snap.notifyOnSyncErrors ?? true
        notifyOnSleepTimerEnd = snap.notifyOnSleepTimerEnd ?? true
        let customSleep = snap.lastCustomSleepTimerMinutes ?? Self.defaultLastCustomSleepTimerMinutes
        let sleepRange = PlaybackService.customSleepTimerMinutesRange
        lastCustomSleepTimerMinutes = min(max(customSleep, sleepRange.lowerBound), sleepRange.upperBound)
        askForAppStoreRating = snap.askForAppStoreRating ?? true
        playVideoAsAudioOnly = snap.playVideoAsAudioOnly ?? false
        volumeAdaptationEnabled = snap.volumeAdaptationEnabled ?? false
        skipSilenceEnabled = snap.skipSilenceEnabled ?? false
        stereoToMonoEnabled = snap.stereoToMonoEnabled ?? false
        preservePitchEnabled = snap.preservePitchEnabled ?? true
        customUserAgent = AppUserAgent.sanitize(snap.customUserAgent ?? "")
        keepScreenOnWhilePlaying = snap.keepScreenOnWhilePlaying ?? false
        continuousPlaybackEnabled = snap.continuousPlaybackEnabled ?? true
        resetPositionWhenMarkedPlayed = snap.resetPositionWhenMarkedPlayed ?? true
        showRemainingTime = snap.showRemainingTime ?? false
        let rewindAfter = snap.rewindAfterPauseSeconds ?? Self.defaultRewindAfterPauseSeconds
        rewindAfterPauseSeconds = Self.rewindAfterPausePresets.contains(rewindAfter)
            ? rewindAfter
            : Self.defaultRewindAfterPauseSeconds
        let smartMark = snap.smartMarkAsPlayedSeconds ?? Self.defaultSmartMarkAsPlayedSeconds
        smartMarkAsPlayedSeconds = Self.clampSmartMarkAsPlayedSeconds(smartMark)
        chartsCountryCode = ChartsCountryPreference.fromStorage(snap.chartsCountryCode).storageValue
        if let orderRaw = snap.homeSectionOrder, !orderRaw.isEmpty {
            var order: [HomeSectionId] = []
            var seen = Set<HomeSectionId>()
            for raw in orderRaw {
                guard let id = HomeSectionId(rawValue: raw), !seen.contains(id) else { continue }
                order.append(id)
                seen.insert(id)
            }
            for id in HomeSectionId.defaultOrder where !seen.contains(id) {
                order.append(id)
                seen.insert(id)
            }
            for id in HomeSectionId.allCases where !seen.contains(id) {
                order.append(id)
            }
            homeSectionOrder = order
        }
        if let hiddenRaw = snap.homeHiddenSections {
            homeHiddenSections = Set(hiddenRaw.compactMap { HomeSectionId(rawValue: $0) })
                .intersection(Set(HomeSectionId.allCases))
        }
        if let sortRaw = snap.subscriptionsSort {
            subscriptionsSort = SubscriptionsSort(rawValue: sortRaw) ?? .recentlyUpdated
        }
        if let catRaw = snap.subscriptionsCategoryFilter {
            subscriptionsCategoryFilter = SubscriptionCategoryFilter.fromStorage(catRaw).storageValue
        }
        if let langRaw = snap.subscriptionsLanguageFilter {
            subscriptionsLanguageFilter = SubscriptionLanguageFilter.fromStorage(langRaw).storageValue
        }
        if let feedEpSortRaw = snap.feedEpisodeSort {
            feedEpisodeSort = FeedEpisodeSort(rawValue: feedEpSortRaw) ?? .newestFirst
        }
        if let feedEpFilterRaw = snap.feedEpisodeFilter {
            feedEpisodeFilter = FeedEpisodeFilter(rawValue: feedEpFilterRaw) ?? .all
        }
        if let inboxSortRaw = snap.inboxSort {
            inboxSort = InboxSort(rawValue: inboxSortRaw) ?? .newestFirst
        }
        if let inboxPodcastFilterRaw = snap.inboxPodcastFilter {
            inboxPodcastFilter = InboxPodcastFilter.fromStorage(inboxPodcastFilterRaw).storageValue
        }
        if let downloadsSortRaw = snap.downloadsSort {
            downloadsSort = DownloadsSort(rawValue: downloadsSortRaw) ?? .newestFirst
        }
        if let downloadsFilterRaw = snap.downloadsFilter {
            downloadsFilter = DownloadsFilter(rawValue: downloadsFilterRaw) ?? .all
        }
        if let downloadsPodcastFilterRaw = snap.downloadsPodcastFilter {
            downloadsPodcastFilter = DownloadsPodcastFilter.fromStorage(downloadsPodcastFilterRaw).storageValue
        }
        if let historySortRaw = snap.historySort {
            historySort = HistorySort(rawValue: historySortRaw) ?? .newestFirst
        }
        if let historyPodcastFilterRaw = snap.historyPodcastFilter {
            historyPodcastFilter = HistoryPodcastFilter.fromStorage(historyPodcastFilterRaw).storageValue
        }
        if let historyLimitRaw = snap.historySizeLimit {
            historySizeLimit = HistorySizeLimit(rawValue: historyLimitRaw) ?? .unlimited
        }
        if let favoritesSortRaw = snap.favoritesSort {
            favoritesSort = FavoritesSort(rawValue: favoritesSortRaw) ?? .newestFirst
        }
        if let favoritesPodcastFilterRaw = snap.favoritesPodcastFilter {
            favoritesPodcastFilter = FavoritesPodcastFilter.fromStorage(favoritesPodcastFilterRaw).storageValue
        }
        if let archivedSortRaw = snap.archivedSort {
            archivedSort = ArchivedSort(rawValue: archivedSortRaw) ?? .newestFirst
        }
        if let filterRaw = snap.allEpisodesFilter {
            allEpisodesFilter = AllEpisodesFilter(rawValue: filterRaw) ?? .all
        }
        if let sortRaw = snap.allEpisodesSort {
            allEpisodesSort = AllEpisodesSort(rawValue: sortRaw) ?? .newestFirst
        }
        queueLocked = snap.queueLocked ?? false
        if let queueFilterRaw = snap.queueFilter {
            queueFilter = QueueFilter(rawValue: queueFilterRaw) ?? .all
        }
        if let queuePodcastFilterRaw = snap.queuePodcastFilter {
            queuePodcastFilter = QueuePodcastFilter.fromStorage(queuePodcastFilterRaw).storageValue
        }
        if let statsRangeRaw = snap.statisticsTimeRange {
            statisticsTimeRange = StatisticsTimeRange(rawValue: statsRangeRaw) ?? .allTime
        }
        if let resetMs = snap.statisticsResetAtEpochMs {
            statisticsResetAtEpochMs = resetMs
        }
    }
}

/// Codable prefs blob inside `app-settings.json` backup entry.
struct AppSettingsBackupSnapshot: Codable, Equatable {
    var theme: String
    /// Absent in older backups → System (no tint override).
    var accentColor: String? = nil
    var defaultPlaybackSpeed: Float
    var storageLimitKind: String
    var storageLimitValue: Int?
    var refreshInterval: String
    var lastFeedRefreshAtEpoch: Double?
    var newEpisodeAction: String?
    var autoDownloadEnabled: Bool
    var autoDownloadEpisodesPerFeed: Int
    /// Absent in older backups → 3 (default).
    var maxParallelDownloads: Int? = 3
    /// Absent in older backups → Unlimited (0). Raw `DownloadEpisodeCacheLimit` value.
    var downloadEpisodeCacheLimit: Int? = 0
    var autoDownloadWifiOnly: Bool
    var manualDownloadWifiOnly: Bool
    var streamWifiOnly: Bool
    var playbackSourcePreference: String
    var autoDeleteAfterPlaying: Bool
    var rewindSeconds: Int
    var fastForwardSeconds: Int
    var skipIntroSeconds: Int
    var skipOutroSeconds: Int
    var notifyOnNewEpisodes: Bool
    var notifyOnDownloadErrors: Bool
    /// Absent in older backups → treated as on (default).
    var notifyOnSyncErrors: Bool? = true
    /// Absent in older backups → treated as on (default).
    var notifyOnSleepTimerEnd: Bool? = true
    /// Absent in older backups → 15 (Android LastValue default). Clamped 1–180 on restore.
    var lastCustomSleepTimerMinutes: Int? = 15
    /// Absent in older backups → treated as on (default).
    var askForAppStoreRating: Bool? = true
    /// Absent in older backups → treated as off (show video when detected).
    var playVideoAsAudioOnly: Bool? = false
    /// Absent in older backups → treated as off (default / moviePlayback session mode).
    var volumeAdaptationEnabled: Bool? = false
    /// Absent in older backups → treated as off (preference only; no AVPlayer skip).
    var skipSilenceEnabled: Bool? = false
    /// Absent in older backups → treated as off (stereo / system default channel count).
    var stereoToMonoEnabled: Bool? = false
    /// Absent in older backups → treated as on (speech-friendly pitch correction).
    var preservePitchEnabled: Bool? = true
    /// Absent in older backups → empty (app default User-Agent).
    var customUserAgent: String? = nil
    /// Absent in older backups → treated as off (allow idle lock).
    var keepScreenOnWhilePlaying: Bool? = false
    /// Absent in older backups → treated as on (auto-next from queue).
    var continuousPlaybackEnabled: Bool? = true
    /// Absent in older backups → treated as on (reset position on mark-played).
    var resetPositionWhenMarkedPlayed: Bool? = true
    /// Absent in older backups → treated as off (show total duration).
    var showRemainingTime: Bool? = false
    /// Absent in older backups → treated as 2 (honest beta default).
    var rewindAfterPauseSeconds: Int? = 2
    /// Absent in older backups → treated as 30 (AntennaPod default).
    var smartMarkAsPlayedSeconds: Int? = 30
    var chartsCountryCode: String
    /// Absent in older backups → default order.
    var homeSectionOrder: [String]? = nil
    /// Absent in older backups → default hidden (Favorites).
    var homeHiddenSections: [String]? = nil
    /// Absent in older backups → recentlyUpdated (default).
    var subscriptionsSort: String? = nil
    /// Absent in older backups → All (empty). Feed category text or empty for All.
    var subscriptionsCategoryFilter: String? = nil
    /// Absent in older backups → All (empty). Feed language code or empty for All.
    var subscriptionsLanguageFilter: String? = nil
    /// Absent in older backups → newestFirst (default).
    var feedEpisodeSort: String? = nil
    /// Absent in older backups → all (default).
    var feedEpisodeFilter: String? = nil
    /// Absent in older backups → newestFirst (default).
    var inboxSort: String? = nil
    /// Absent in older backups → All (empty). Feed UUID string or empty for All.
    var inboxPodcastFilter: String? = nil
    /// Absent in older backups → newestFirst (default).
    var downloadsSort: String? = nil
    /// Absent in older backups → all (default).
    var downloadsFilter: String? = nil
    /// Absent in older backups → All (empty). Feed UUID string or empty for All.
    var downloadsPodcastFilter: String? = nil
    /// Absent in older backups → newestFirst (default).
    var historySort: String? = nil
    /// Absent in older backups → All (empty). Feed UUID string or empty for All.
    var historyPodcastFilter: String? = nil
    /// Absent in older backups → Unlimited (0). Raw `HistorySizeLimit` value.
    var historySizeLimit: Int? = 0
    /// Absent in older backups → newestFirst (default).
    var favoritesSort: String? = nil
    /// Absent in older backups → All (empty). Feed UUID string or empty for All.
    var favoritesPodcastFilter: String? = nil
    /// Absent in older backups → newestFirst (default).
    var archivedSort: String? = nil
    /// Absent in older backups → all (default).
    var allEpisodesFilter: String? = nil
    /// Absent in older backups → newestFirst (default).
    var allEpisodesSort: String? = nil
    /// Absent in older backups → unlocked (false).
    var queueLocked: Bool? = false
    /// Absent in older backups → all (default).
    var queueFilter: String? = nil
    /// Absent in older backups → All (empty). Feed UUID string or empty for All.
    var queuePodcastFilter: String? = nil
    /// Absent in older backups → allTime (default).
    var statisticsTimeRange: String? = nil
    /// Absent in older backups → 0 (no reset baseline).
    var statisticsResetAtEpochMs: Int64? = nil
}
