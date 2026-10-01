import Foundation

/// Chapter marker from feed (Podlove Simple Chapters / Podcast Index) or remote JSON.
struct PodcastChapter: Identifiable, Hashable, Codable {
    var id: String { "\(startTimeSeconds)|\(title)" }
    var title: String
    /// Start offset from episode beginning.
    var startTimeSeconds: Double
    var href: String?
    var imageUrl: String?

    init(title: String, startTimeSeconds: Double, href: String? = nil, imageUrl: String? = nil) {
        self.title = title
        self.startTimeSeconds = startTimeSeconds
        self.href = href
        self.imageUrl = imageUrl
    }
}

struct PodcastEpisode: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var link: String?
    var pubDateEpochMs: Int64?
    var downloadUrl: String?
    var mimeType: String?
    var size: Int64
    var transcriptUrl: String?
    /// Inline chapters (PSC / Atom) parsed from the feed item.
    var chapters: [PodcastChapter]
    /// Podcast Index `podcast:chapters` remote JSON URL (fetched lazily when needed).
    var podcastIndexChapterUrl: String?

    init(
        id: String,
        title: String,
        link: String? = nil,
        pubDateEpochMs: Int64? = nil,
        downloadUrl: String? = nil,
        mimeType: String? = nil,
        size: Int64 = 0,
        transcriptUrl: String? = nil,
        chapters: [PodcastChapter] = [],
        podcastIndexChapterUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.link = link
        self.pubDateEpochMs = pubDateEpochMs
        self.downloadUrl = downloadUrl
        self.mimeType = mimeType
        self.size = size
        self.transcriptUrl = transcriptUrl
        self.chapters = chapters
        self.podcastIndexChapterUrl = podcastIndexChapterUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        link = try c.decodeIfPresent(String.self, forKey: .link)
        pubDateEpochMs = try c.decodeIfPresent(Int64.self, forKey: .pubDateEpochMs)
        downloadUrl = try c.decodeIfPresent(String.self, forKey: .downloadUrl)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        transcriptUrl = try c.decodeIfPresent(String.self, forKey: .transcriptUrl)
        chapters = try c.decodeIfPresent([PodcastChapter].self, forKey: .chapters) ?? []
        podcastIndexChapterUrl = try c.decodeIfPresent(String.self, forKey: .podcastIndexChapterUrl)
    }
}

struct PodcastFeed: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var feedUrl: String
    var siteLink: String?
    var imageUrl: String?
    var descriptionText: String?
    var episodes: [PodcastEpisode]
}

/// Per-episode playback progress and played flag (keyed by episode id / guid).
struct EpisodePlaybackState: Hashable, Codable {
    var positionSeconds: Double
    var durationSeconds: Double
    var isPlayed: Bool
    var updatedAtEpochMs: Int64
    /// Last time the user played or marked this episode played (History sort key).
    /// Distinct from `updatedAtEpochMs`, which also bumps on mark-unplayed.
    var lastPlayedAtEpochMs: Int64?

    static func empty(nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> EpisodePlaybackState {
        EpisodePlaybackState(
            positionSeconds: 0,
            durationSeconds: 0,
            isPlayed: false,
            updatedAtEpochMs: nowMs,
            lastPlayedAtEpochMs: nil
        )
    }

    init(
        positionSeconds: Double,
        durationSeconds: Double,
        isPlayed: Bool,
        updatedAtEpochMs: Int64,
        lastPlayedAtEpochMs: Int64? = nil
    ) {
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.isPlayed = isPlayed
        self.updatedAtEpochMs = updatedAtEpochMs
        self.lastPlayedAtEpochMs = lastPlayedAtEpochMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        positionSeconds = try c.decodeIfPresent(Double.self, forKey: .positionSeconds) ?? 0
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        isPlayed = try c.decodeIfPresent(Bool.self, forKey: .isPlayed) ?? false
        updatedAtEpochMs = try c.decodeIfPresent(Int64.self, forKey: .updatedAtEpochMs)
            ?? Int64(Date().timeIntervalSince1970 * 1000)
        lastPlayedAtEpochMs = try c.decodeIfPresent(Int64.self, forKey: .lastPlayedAtEpochMs)
        // Migrate older `playback.json` without `lastPlayedAtEpochMs`.
        if lastPlayedAtEpochMs == nil, isPlayed || positionSeconds > 0 {
            lastPlayedAtEpochMs = updatedAtEpochMs
        }
    }

    /// Whether this state should appear in History (played or in-progress).
    var belongsInHistory: Bool {
        isPlayed || positionSeconds > 1
    }

    private enum CodingKeys: String, CodingKey {
        case positionSeconds, durationSeconds, isPlayed, updatedAtEpochMs, lastPlayedAtEpochMs
    }
}

/// Episode row for the Inbox tab (cross-feed unplayed list).
struct InboxEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
}

/// Episode hit from local library search (title / feed title / descriptions).
struct LibraryEpisodeHit: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let feedId: UUID
}

/// Episode row for History (played / in-progress), newest last-played first.
struct HistoryEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let lastPlayedAtEpochMs: Int64
}

/// Episode row for Favorites (starred), newest favorited first.
struct FavoriteEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let favoritedAtEpochMs: Int64
}

/// Episode row for Archived, newest archived first.
struct ArchivedEpisode: Identifiable, Hashable {
    var id: String { episode.id }
    let episode: PodcastEpisode
    let feedTitle: String
    let archivedAtEpochMs: Int64
}

enum ChapterIndexing {
    /// Index of the chapter active at `positionSeconds`, or `nil` if before the first chapter / empty.
    static func currentIndex(in chapters: [PodcastChapter], at positionSeconds: Double) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var current: Int?
        for (i, chapter) in chapters.enumerated() {
            if chapter.startTimeSeconds <= positionSeconds {
                current = i
            } else {
                break
            }
        }
        return current
    }
}

/// Approximate listening time attributed to one episode from `playback.json`.
/// Played → `durationSeconds` when known (position is cleared on mark-played);
/// in-progress → `positionSeconds`. Not cumulative across rewinds / re-listens / speed.
enum ListeningTimeEstimate {
    static func seconds(for state: EpisodePlaybackState) -> Double {
        if state.isPlayed {
            if state.durationSeconds.isFinite, state.durationSeconds > 0 {
                return state.durationSeconds
            }
            return 0
        }
        if state.positionSeconds > 1 {
            return state.positionSeconds
        }
        return 0
    }

    static func hasMeaningfulData(_ state: EpisodePlaybackState) -> Bool {
        state.isPlayed || state.positionSeconds > 1
    }
}

/// Per-podcast rollup for Statistics (top list).
struct FeedListeningStats: Identifiable, Hashable {
    let id: UUID
    let feedTitle: String
    let playedEpisodeCount: Int
    let inProgressEpisodeCount: Int
    let approximateListenedSeconds: Double
}

/// Library-wide listening stats derived from `playback.json` (honest approximation).
struct ListeningStatistics: Hashable {
    var playedEpisodeCount: Int
    var inProgressEpisodeCount: Int
    var approximateListenedSeconds: Double
    var topPodcasts: [FeedListeningStats]

    var isEmpty: Bool {
        playedEpisodeCount == 0 && inProgressEpisodeCount == 0
    }

    static let empty = ListeningStatistics(
        playedEpisodeCount: 0,
        inProgressEpisodeCount: 0,
        approximateListenedSeconds: 0,
        topPodcasts: []
    )
}

/// Per-podcast rollup for Echo (year in review).
struct EchoFeedStats: Identifiable, Hashable {
    let id: UUID
    let feedTitle: String
    let playedEpisodeCount: Int
    let approximateListenedSeconds: Double
}

/// Calendar-year summary from playback / favorites (honest approximation; same limits as Statistics).
struct EchoYearSummary: Hashable {
    /// Calendar year (e.g. 2026).
    var year: Int
    /// Episodes with `isPlayed` whose `lastPlayedAt` falls in this year.
    var playedEpisodeCount: Int
    var approximateListenedSeconds: Double
    var topPodcasts: [EchoFeedStats]
    /// Favorites whose favorited-at timestamp falls in this year (`favorites.json`).
    var favoritesCountThisYear: Int
    /// All currently starred episodes (any year).
    var favoritesTotalCount: Int

    var isEmpty: Bool {
        playedEpisodeCount == 0 && approximateListenedSeconds <= 0 && favoritesCountThisYear == 0
    }

    static func empty(year: Int) -> EchoYearSummary {
        EchoYearSummary(
            year: year,
            playedEpisodeCount: 0,
            approximateListenedSeconds: 0,
            topPodcasts: [],
            favoritesCountThisYear: 0,
            favoritesTotalCount: 0
        )
    }
}
