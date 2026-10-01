import Foundation

/// Chapter marker from feed (Podlove Simple Chapters / Podcast Index), remote JSON, or local media-file tags.
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
    /// Podcast Index transcript MIME (`application/json`, `text/vtt`, `application/srt`, …).
    var transcriptType: String?
    /// Chapters: feed PSC/Atom, fetched Podcast Index JSON, or media-file tags (when persisted after local read).
    var chapters: [PodcastChapter]
    /// Podcast Index `podcast:chapters` remote JSON URL (fetched lazily when needed).
    var podcastIndexChapterUrl: String?
    /// Episode shownotes / description from RSS (`description` / `content:encoded` / Atom `summary` / `content`).
    /// May contain HTML; UI strips tags to plain text for beta display.
    var descriptionText: String?
    /// Feed-declared duration in seconds (`itunes:duration` / Media RSS `media:content@duration`).
    /// `0` = unknown / missing. Prefer this for list rows; playback may refine via `EpisodePlaybackState.durationSeconds`.
    var durationSeconds: Double
    /// iTunes season number from `itunes:season`. `nil` = not in feed — never invent sequential seasons.
    var seasonNumber: Int?
    /// iTunes episode number from `itunes:episode`. `nil` = not in feed — never invent sequential episode numbers.
    var episodeNumber: Int?
    /// iTunes episode type from `itunes:episodeType` (`full` / `trailer` / `bonus`). `nil` = not in feed.
    var episodeType: String?

    /// Feed provides a remote transcript URL (no on-device STT).
    var hasTranscriptURL: Bool {
        guard let transcriptUrl, !transcriptUrl.isEmpty else { return false }
        return true
    }

    /// Video episode when enclosure MIME is `video/*` or the media URL ends in a common video extension.
    /// Used by the full player video surface (beta lite). Not every `video/mp4` feed is guaranteed playable.
    var isVideo: Bool {
        if let mime = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           mime.hasPrefix("video/") {
            return true
        }
        return Self.videoFileExtension(from: downloadUrl) != nil
    }

    private static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm"]

    /// Lowercased path extension when it looks like a video file; ignores query/fragment.
    private static func videoFileExtension(from urlString: String?) -> String? {
        guard let urlString, !urlString.isEmpty else { return nil }
        let path: String
        if let url = URL(string: urlString) {
            path = url.path
        } else {
            path = urlString.split(separator: "?", maxSplits: 1).first.map(String.init) ?? urlString
        }
        let ext = (path as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext) ? ext : nil
    }

    init(
        id: String,
        title: String,
        link: String? = nil,
        pubDateEpochMs: Int64? = nil,
        downloadUrl: String? = nil,
        mimeType: String? = nil,
        size: Int64 = 0,
        transcriptUrl: String? = nil,
        transcriptType: String? = nil,
        chapters: [PodcastChapter] = [],
        podcastIndexChapterUrl: String? = nil,
        descriptionText: String? = nil,
        durationSeconds: Double = 0,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        episodeType: String? = nil
    ) {
        self.id = id
        self.title = title
        self.link = link
        self.pubDateEpochMs = pubDateEpochMs
        self.downloadUrl = downloadUrl
        self.mimeType = mimeType
        self.size = size
        self.transcriptUrl = transcriptUrl
        self.transcriptType = transcriptType
        self.chapters = chapters
        self.podcastIndexChapterUrl = podcastIndexChapterUrl
        self.descriptionText = descriptionText
        self.durationSeconds = durationSeconds
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.episodeType = episodeType
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
        transcriptType = try c.decodeIfPresent(String.self, forKey: .transcriptType)
        chapters = try c.decodeIfPresent([PodcastChapter].self, forKey: .chapters) ?? []
        podcastIndexChapterUrl = try c.decodeIfPresent(String.self, forKey: .podcastIndexChapterUrl)
        descriptionText = try c.decodeIfPresent(String.self, forKey: .descriptionText)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber)
        episodeType = try c.decodeIfPresent(String.self, forKey: .episodeType)
    }

    /// Non-empty shownotes / description from the feed (may still contain HTML).
    var hasDescriptionText: Bool {
        guard let descriptionText else { return false }
        return !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Finite feed duration greater than zero (hide when unknown).
    var hasKnownDuration: Bool {
        durationSeconds.isFinite && durationSeconds > 0
    }

    /// Compact season/episode from iTunes tags only (`S2 E5`, `S2`, or `E5`).
    /// `nil` when neither season nor episode is in the feed — never invents numbers.
    var seasonEpisodeCaption: String? {
        switch (seasonNumber, episodeNumber) {
        case let (season?, episode?):
            return "S\(season) E\(episode)"
        case let (season?, nil):
            return "S\(season)"
        case let (nil, episode?):
            return "E\(episode)"
        default:
            return nil
        }
    }

    /// VoiceOver phrasing for season/episode numbers when present.
    var seasonEpisodeAccessibilityLabel: String? {
        switch (seasonNumber, episodeNumber) {
        case let (season?, episode?):
            return String(localized: "Season \(season), Episode \(episode)")
        case let (season?, nil):
            return String(localized: "Season \(season)")
        case let (nil, episode?):
            return String(localized: "Episode \(episode)")
        default:
            return nil
        }
    }

    /// Localized Trailer / Bonus when `itunes:episodeType` is trailer or bonus.
    /// `full` and unknown/missing stay hidden (full is the default).
    var episodeTypeCaption: String? {
        guard let raw = episodeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "trailer":
            return String(localized: "Trailer")
        case "bonus":
            return String(localized: "Bonus")
        default:
            return nil
        }
    }
}

struct PodcastFeed: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var feedUrl: String
    var siteLink: String?
    var imageUrl: String?
    /// Channel / feed description from RSS (`description` / Atom `subtitle` / `summary`). May contain HTML.
    var descriptionText: String?
    /// Podcast author when the feed provides it (`itunes:author` / Atom `author`/`name` / RSS `managingEditor`).
    /// Nil or blank when absent — never invented from discovery hints alone.
    var author: String?
    var episodes: [PodcastEpisode]

    /// Non-empty feed description (may still contain HTML).
    var hasDescriptionText: Bool {
        guard let descriptionText else { return false }
        return !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Trimmed non-empty author for UI / VoiceOver / search. Hidden when missing.
    var displayAuthor: String? {
        guard let author else { return nil }
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
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
    /// AntennaPod-like: if farther than this into the current chapter, Previous restarts it.
    static let previousRestartThresholdSeconds: Double = 2

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

    /// Seek target for Previous chapter, or `nil` when there are no chapters.
    /// If >`previousRestartThresholdSeconds` into the current chapter → chapter start;
    /// otherwise → previous chapter start (or `0` on the first chapter).
    static func previousSeekSeconds(in chapters: [PodcastChapter], at positionSeconds: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        guard let index = currentIndex(in: chapters, at: positionSeconds) else {
            return 0
        }
        let start = chapters[index].startTimeSeconds
        if positionSeconds - start > previousRestartThresholdSeconds {
            return start
        }
        if index == 0 {
            return 0
        }
        return chapters[index - 1].startTimeSeconds
    }

    /// Seek target for Next chapter (start of the chapter after the current one), or `nil`
    /// when there are no chapters / already on the last chapter.
    static func nextSeekSeconds(in chapters: [PodcastChapter], at positionSeconds: Double) -> Double? {
        guard !chapters.isEmpty else { return nil }
        if let index = currentIndex(in: chapters, at: positionSeconds) {
            let next = index + 1
            guard next < chapters.count else { return nil }
            return chapters[next].startTimeSeconds
        }
        // Before the first chapter → jump to it.
        return chapters[0].startTimeSeconds
    }

    /// End of chapter at `index`: next chapter start, or `episodeDurationSeconds` for the last
    /// chapter when a known finite duration is provided. `nil` when index is invalid, or when
    /// this is the last chapter and episode duration is unknown (cannot invent an end).
    /// Wall-clock offsets only — no playback-speed divide.
    static func endSeconds(
        in chapters: [PodcastChapter],
        atIndex index: Int,
        episodeDurationSeconds: Double?
    ) -> Double? {
        guard index >= 0, index < chapters.count else { return nil }
        let next = index + 1
        if next < chapters.count {
            let end = chapters[next].startTimeSeconds
            guard end.isFinite, end >= chapters[index].startTimeSeconds else { return nil }
            return end
        }
        guard let duration = episodeDurationSeconds,
              duration.isFinite,
              duration > 0 else {
            return nil
        }
        let start = chapters[index].startTimeSeconds
        guard duration >= start else { return nil }
        return duration
    }

    /// Chapter duration = end − start when end is known. `nil` when end cannot be derived
    /// (e.g. last chapter without episode duration).
    static func durationSeconds(
        in chapters: [PodcastChapter],
        atIndex index: Int,
        episodeDurationSeconds: Double?
    ) -> Double? {
        guard let end = endSeconds(in: chapters, atIndex: index, episodeDurationSeconds: episodeDurationSeconds),
              index >= 0, index < chapters.count else {
            return nil
        }
        let start = chapters[index].startTimeSeconds
        let duration = end - start
        guard duration.isFinite, duration >= 0 else { return nil }
        return duration
    }

    /// Remaining wall-clock time in the chapter at `index`: `max(0, end − position)`.
    /// `nil` when end is unknown. Does not require the chapter to be current — callers decide
    /// when to show remaining (typically only for the active chapter).
    static func remainingSeconds(
        in chapters: [PodcastChapter],
        atIndex index: Int,
        positionSeconds: Double,
        episodeDurationSeconds: Double?
    ) -> Double? {
        guard let end = endSeconds(in: chapters, atIndex: index, episodeDurationSeconds: episodeDurationSeconds) else {
            return nil
        }
        guard positionSeconds.isFinite else { return nil }
        return max(0, end - positionSeconds)
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
